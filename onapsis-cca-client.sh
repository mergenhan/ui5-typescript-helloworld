#!/bin/bash

TRUSTED_HASH="0c9dae2ef85969593cdbd56e19b157850e4ec821f099e43589982062e79e0cab"
echo "Trusted hash: $TRUSTED_HASH"
CURRENT_HASH=$(sed '3d' "$0" | sha256sum | awk '{print $1}')
if [ "$CURRENT_HASH" != "$TRUSTED_HASH" ]; then
  echo "Current hash: $CURRENT_HASH"
  echo "ERROR: Script has been modified. To fix this, please follow these steps:"
  echo "1. Remove this file from the repository;"
  echo "2. Copy the original version provided by Onapsis. You can download it from the Customer Portal;"
  echo "3. Push the original file to the git remote repository."
  echo "Exiting."
  exit 1
fi
echo "Script integrity verified. Continuing..."

shopt -s lastpipe

START_SCAN_BODY_PATTERN='{
  "engine_type": "GIT",
  "scan_information": {
    "name": "%scan_name%",
    "description": "%description%"
  },
  "asset": {
    "type": "GITURL",
    "url": "%git_repo_url%"
  },
  "configuration": {
    "origin": "PIPER"
  },
  "scan_scope": {
    "languages": [
      "%app_type%"
    ],
    "branch_name": "%git_branch%",
    "exclude_packages": []
  }
}'

# Result variables
JOB_ID_RESULT=""
SCAN_STATUS=""
CHILD_JOB_ID=""
HTTP_CODE=""
HTTP_RESPONSE_BODY=""
MANDATORY_FINDING_COUNT=0
OPTIONAL_FINDING_COUNT=0

# call_api(api_url, http_method, jwt, request_body)
# Function to make HTTP calls.
# Arguments:
#   1. API URL
#   2. HTTP Method (GET, POST, etc.)
#   3. JWT
#   4. Request Body (optional, for POST requests)
call_api() {

  local api_url=$1
  local http_method=$2
  local jwt=$3
  local request_body=$4

  local response
  if $TRUST_SELF_SIGNED_SSL; then
    response=$(curl -k --no-progress-meter -i -X "$http_method" "$api_url" \
        -H "Authorization: Bearer $jwt" \
        -H "Content-Type: application/json" \
        -d "$request_body")
  else
    echo "TRUST_SELF_SIGNED_SSL is false. If the CCA certificate is self-signed, the API call will fail."
    response=$(curl --no-progress-meter -i -X "$http_method" "$api_url" \
        -H "Authorization: Bearer $jwt" \
        -H "Content-Type: application/json" \
        -d "$request_body")
  fi

  HTTP_CODE=$(echo "$response" | grep -oE '^HTTP/[0-9.]+ [0-9]+' | awk '{print $2}')
  HTTP_RESPONSE_BODY=$(echo "$response" | sed -n '/^\r$/,$p' | sed '1d')

  if [ -z "$HTTP_RESPONSE_BODY" ]; then
    HTTP_RESPONSE_BODY="<empty>"
  fi

  echo "HTTP Code: $HTTP_CODE"
}

# start_scan(jwt, scan_name, git_repo_url, git_branch, app_type)
# Function to start a GIT repo scan.
# Arguments:
#   1. JWT
#   2. Scan Name
#   3. Git Repository URL
#   4. Git Branch Name
#   5. Application Type (ABAP, SAPUI5)
start_scan() {

  local api_url="$CCA_URL/cca/v1.0/scan"
  local jwt=$1
  local scan_name=$2
  local description="Scan initiated by Piper CCA Client"
  local git_repo_url=$3
  local git_branch=$4
  local app_type=$5
  local request_body=$START_SCAN_BODY_PATTERN

  # Replace placeholders in the JSON body
  request_body=${request_body//%scan_name%/$scan_name}
  request_body=${request_body//%description%/$description}
  request_body=${request_body//%git_repo_url%/$git_repo_url}
  request_body=${request_body//%app_type%/$app_type}
  request_body=${request_body//%git_branch%/$git_branch}

  printf "Starting scan with the following parameters:
API URL: %s
Scan Name: %s
Scanned Git repository URL: %s
Scanned Git branch: %s
Application Type: %s\n" "$api_url" "$scan_name" "$git_repo_url" "$git_branch" "$app_type"

  call_api "$api_url" "POST" "$jwt" "$request_body"

  local job_id
  job_id=$(echo "$HTTP_RESPONSE_BODY" | grep -o '"job_id":[^,]*' | sed 's/"job_id":"\([^"]*\)"/\1/')

  if [ -z "$job_id" ]; then
    echo "Failed to start scan. Response: $HTTP_RESPONSE_BODY"
    exit 2
  fi

  echo "Scan started successfully. Job ID: $job_id"
  JOB_ID_RESULT="$job_id"
}

# get_status(job_id, jwt)
# Function to get the status of a scan job.
# Arguments:
#   1. Job ID
#   2. JWT
get_status() {

  local job_id="$1"
  local jwt=$2
  local api_url="$CCA_URL/cca/v1.2/jobs/$job_id"

  printf "Getting status for Job ID: %s..." "$1"

  call_api "$api_url" "GET" "$jwt" ""

  local status
  status=$(echo "$HTTP_RESPONSE_BODY" | grep -m 1 -o '"status":[^,]*' | head -1 | sed 's/"status":"\([^"]*\)"/\1/')

  if [ -z "$status" ]; then
    echo "Failed to get scan status. Response: $HTTP_RESPONSE_BODY"
    exit 3
  fi

  local progress
  progress=$(echo "$HTTP_RESPONSE_BODY" | grep -o '"progress":[^,]*' | sed 's/"progress":\([^"]*\)/\1/')

  local child_job_id
  child_job_id=$(echo "$HTTP_RESPONSE_BODY" | grep -o '"children":\s*\[[^]]*' | sed -n 's/.*\["\([^"]*\)".*/\1/p')
  CHILD_JOB_ID="$child_job_id"

  echo "Job status: $status, progress: $progress%"
  SCAN_STATUS="$status"
}

# get_result_metrics(job_id, jwt)
# Function to get the result metrics of a completed scan job.
# Arguments:
#   1. Job ID
#   2. JWT
get_result_metrics() {

  local job_id="$1"
  local jwt=$2
  local api_url="$CCA_URL/cca/v1.2/jobs/$job_id/result/metrics"

  printf "Getting result metrics for Job ID: %s..." "$job_id"

  call_api "$api_url" "GET" "$jwt" ""

  if [ "$HTTP_CODE" != "200" ]; then
    echo "Failed to get scan result metrics. Response: $HTTP_RESPONSE_BODY"
    exit 4
  fi

  local success
  success=$(echo "$HTTP_RESPONSE_BODY" | grep -o '"success":[^,]*' | sed 's/"success":\([^"]*\)/\1/')

  if [ "$success" != "true" ]; then
    echo "Failed to get scan result metrics. Response: $HTTP_RESPONSE_BODY"
    exit 5
  fi

  # Extract and print each metric's name and value
  echo "$HTTP_RESPONSE_BODY" | grep -o '{"name":"[^"]*","value":"[^"]*"}' |
   while read -r metric;
   do
    name=$(echo "$metric" | grep -o '"name":"[^"]*' | sed 's/"name":"//')
    value=$(echo "$metric" | grep -o '"value":"[^"]*' | sed 's/"value":"//')

    case $name in
      "num_findings")
        echo "Total Findings: $value"
        ;;
      "num_mandatory")
        MANDATORY_FINDING_COUNT=$value
        echo "Mandatory Findings: $value"
        ;;
      "num_optional")
        OPTIONAL_FINDING_COUNT=$value
        echo "Optional Findings: $value"
        ;;
      "total_time_used")
        echo "Total Scan Time (seconds): $value"
        ;;
      "scan_time_used")
        echo "Scan Time (seconds): $value"
        ;;
      *)
        echo "$name: $value"
        ;;
    esac

   done
}

# Parameter validation
if [ -z "$CCA_JWT" ]; then
  echo "ERROR: CCA_JWT is not set. Please set it as an additional variable in the configuration of the pipeline. Exiting."
  exit 6
fi

if [ -z "$CCA_URL" ]; then
  echo "ERROR: CCA_URL is not set. Please set it as an additional variable in the configuration of the pipeline. Exiting."
  exit 7
fi
if [ -z "$APP_TYPE" ]; then
  echo "ERROR: APP_TYPE is not set. Please set it as an additional variable in the configuration of the pipeline. Exiting."
  exit 8
fi

# Main script execution
if ! start_scan "$CCA_JWT" "$JOB_NAME" "$GIT_URL" "$GIT_BRANCH" "$APP_TYPE"; then
  exit 9
fi

# Polling for scan status with exponential backoff
# The delay increases by a factor of 1.1 each iteration, starting at 10s, capped at 900s (15m)
# The effective timeout is approximately 86772s, or about 24 hours
iterations=71
start_value=10
ratio="1.1"
max_delay=900
i=0
until [[ "$i" -gt "$iterations" || "$SCAN_STATUS" == "SUCCESS" || "$SCAN_STATUS" == "FAILED" ]]
do
  delay=$(awk -v a="$start_value" -v r="$ratio" -v i="$i" 'BEGIN { print a * (r^i) }')
  delay=${delay%.*}  # Convert to integer by removing decimal part
  if (( delay >= max_delay )); then
    delay=("$max_delay")
  fi
  printf "Waiting %ss for the scan to finish..." "${delay[0]}"
  sleep "${delay[0]}"
  ((i++))
  if ! get_status "$JOB_ID_RESULT" "$CCA_JWT"; then
    exit 10
  fi
done

get_result_metrics "$JOB_ID_RESULT" "$CCA_JWT"

echo "*******************************************************************************"
echo "The findings can be viewed here: $CCA_URL/ui/#/admin/scans/$JOB_ID_RESULT/$CHILD_JOB_ID/findings"
echo "The scan result archive can be downloaded from: $CCA_URL/cca/v1.2/jobs/$JOB_ID_RESULT/result?format=ZIP"
echo "*******************************************************************************"

if [[ $FAIL_ON_MANDATORY_FINDINGS == "true" &&  $MANDATORY_FINDING_COUNT -gt 0 ]]; then
  echo "The scan found mandatory findings and is configured to fail the pipeline. (FAIL_ON_MANDATORY_FINDINGS is true)"
  exit 11
fi

if [[ $FAIL_ON_OPTIONAL_FINDINGS == "true" &&  $OPTIONAL_FINDING_COUNT -gt 0 ]]; then
  echo "The scan found optional findings and is configured to fail the pipeline. (FAIL_ON_OPTIONAL_FINDINGS is true)"
  exit 12
fi
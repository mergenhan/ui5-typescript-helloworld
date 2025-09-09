/*
(function(){
    "use strict";
    jQuery.sap.declare("de.virtualforge.cp4h.datatypes.VFChartT");
    jQuery.sap.require("sap.ui.base.DataType");
    de.virtualforge.cp4h.datatypes.VFChartT = sap.ui.base.DataType.createType(
        "de.virtualforge.cp4h.datatypes.VFChartT",
        {
            isValid : function(sValue) {
                return true; // TODO
            }
        },
        sap.ui.base.DataType.getType('object')
        );
}()); //*/

(function() {
	"use strict";
	jQuery.sap.declare("de.virtualforge.cp4h.controls.VFChart");
	sap.ui.core.Control.extend("de.virtualforge.cp4h.controls.VFChart", {
		metadata: {
			properties: {
				width: {
					type: "sap.ui.core.CSSSize",
					defaultValue: "400px"
				},
				height: {
					type: "sap.ui.core.CSSSize",
					defaultValue: "400px"
				},
				title: {
					type: "string"
				},
				label: { type: "string" },
				chartType: {
					type: "string"
				},
				a: {
					type: "int"
				},
				b: {
					type: "int"
				},
				c: {
					type: "int"
				},
				d: {
					type: "int"
				}
			}
		},

		onAfterRendering: function(evt) {
			var oControl = evt.srcControl;
			var canvas = document.getElementById("canvas-" + oControl.getId());
			var canvasctx = canvas.getContext('2d');
			var chartType = oControl.getChartType();

            var data =
                [ oControl.getA()
                , oControl.getB()
                , oControl.getC()
                , oControl.getD()];

			var datasets = {
				labels: ["Stocks", "Account", "Real estate", "Credit card"],
				datasets: [{
					label: oControl.getLabel(),
					data: data,
					backgroundColor: [
                'rgba(255, 99, 132, 0.2)',
                'rgba(200, 80, 35, 0.2)',
                'rgba(255, 206, 86, 0.2)',
                'rgba(75, 192, 192, 0.2)'
            ],
					borderColor: [
                'rgba(255,99,132,1)',
                'rgba(54, 162, 235, 1)',
                'rgba(255, 206, 86, 1)',
                'rgba(75, 192, 192, 1)'
            ],
					borderWidth: 1
        }]
			};

			var options = {
				scales: {
					yAxes: [{
						ticks: {
							beginAtZero: true
						}
            }]
				}
			};

			var chart = new Chart(canvasctx, {
				type: chartType,
				data: datasets,
				options: options
			});
		},

		renderer: {
			render: function(oRm, oControl) {
				oRm.write("<div")
				oRm.writeControlData(oControl);
				oRm.write(">");
				oRm.write("<h1>" + oControl.getTitle() + "</h1>");
			    //oRm.writeEscaped("<h1>" + oControl.getTitle() + "</h1>"); 
				oRm.write("<canvas id=\"canvas-" + oControl.getId() + "\"");
				oRm.addStyle("width", oControl.getWidth());
				oRm.addStyle("height", oControl.getHeight());
				oRm.writeStyles();
				oRm.write("></canvas></div>");
			}
		}
	});
}());
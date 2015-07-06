/*
 * GanttBarPanelController.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * Deal with Zoom In/Out and a few other events of the GanttBarPanel.
 */
Ext.define('GanttEditor.controller.GanttBarPanelController', {
    extend: 'Ext.app.Controller',
    zoomFactor: 5.0,                                     // Fast or slow zooming? 2.0 is fast, 10.0 is very slow
    refs: [
	{ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
	{ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],

    init: function() {
	this.control({
	    '#buttonZoomIn': { click: this.onButtonZoomIn },
	    '#buttonZoomOut': { click: this.onButtonZoomOut },
	    '#buttonZoomCenter': { click: this.onButtonZoomCenter }
	});
    },

    /**
     * Zoom In
     */
    onButtonZoomIn: function() {
        var me = this;
	var ganttBarPanel = this.getGanttBarPanel();
	var zoomFactor = me.zoomFactor;

	var axisStartTime = ganttBarPanel.axisStartDate.getTime();
	var axisEndTime = ganttBarPanel.axisEndDate.getTime();
	var axisEndX = ganttBarPanel.axisEndX;
	var diff = ((axisEndTime - axisStartTime) / (1 + 2 / zoomFactor)) / zoomFactor;	     // Reverse the the effect of ZoomOut
	
	ganttBarPanel.axisStartDate = new Date(axisStartTime + diff);
	ganttBarPanel.axisEndDate = new Date(axisEndTime - diff);
	// ganttBarPanel.axisEndX = Math.round(axisEndX * zoomFactor);

        me.getGanttBarPanel().redraw();
    },

    /**
     * Zoom Out
     */
    onButtonZoomOut: function() {
        var me = this;
	var ganttBarPanel = this.getGanttBarPanel();
	var zoomFactor = me.zoomFactor;

	var axisStartTime = ganttBarPanel.axisStartDate.getTime();
	var axisEndTime = ganttBarPanel.axisEndDate.getTime();
	var axisEndX = ganttBarPanel.axisEndX;
	var diff = (axisEndTime - axisStartTime) / zoomFactor;
	
	ganttBarPanel.axisStartDate = new Date(axisStartTime - diff);
	ganttBarPanel.axisEndDate = new Date(axisEndTime + diff);
	// ganttBarPanel.axisEndX = Math.round(axisEndX / zoomFactor);

        me.getGanttBarPanel().redraw();
    },

    /**
     * Zoom Center
     * Set the scroll bar so that the currently selected task
     * (or the main task if no task is selected) is shown in 
     * the middle of the GanttBarPanel.
     */
    onButtonZoomCenter: function() {
        var me = this;
	var ganttBarPanel = this.getGanttBarPanel();


        me.getGanttBarPanel().redraw();
    }

});

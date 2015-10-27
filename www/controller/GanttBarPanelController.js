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
    refs: [
	{ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
	{ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],
    
    debug: false,
    zoomFactor: 5.0,                                     // Fast or slow zooming? 2.0 is fast, 10.0 is very slow

    init: function() {
	var me = this;
	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.init: Starting');
	me.control({
	    '#buttonZoomIn': { click: me.onButtonZoomIn },
	    '#buttonZoomOut': { click: me.onButtonZoomOut },
	    '#buttonZoomCenter': { click: me.onButtonZoomCenter }
	});
	
	// Redraw GanttBars when all events are handled
	Ext.globalEvents.on("idle", this.onIdle, me)

	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.init: Finished');
    },

    /**
     * Called before passing control back to the Browser.
     * No logging, because this routine is called so frequently.
     */
    onIdle: function() {
	var me = this;
	var ganttBarPanel = me.getGanttBarPanel();
	if (ganttBarPanel.needsRedraw) {
	    ganttBarPanel.redraw();
	}
    },

    /**
     * Zoom In
     */
    onButtonZoomIn: function() {
        var me = this;
	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomIn: Starting');
	var ganttBarPanel = me.getGanttBarPanel();
	var scrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
	var zoomFactor = me.zoomFactor;

	var axisStartTime = ganttBarPanel.axisStartDate.getTime();
	var axisEndTime = ganttBarPanel.axisEndDate.getTime();
	var axisEndX = ganttBarPanel.axisEndX;
	var scrollX = scrollableEl.getScrollLeft();
	var surfaceWidth = ganttBarPanel.getSize().width;
	
	// Calculate the current "central time" in the middle of the view area
	var centralX = scrollX + Math.round(surfaceWidth / 2);                     // X position of the center of the visible area
	var oldCentralTime = ganttBarPanel.x2time(centralX);
	
	// Calculate the diff for the axis start- and end time.
	var diff = ((axisEndTime - axisStartTime) / (1 + 2 / zoomFactor)) / zoomFactor;	     // Reverse the the effect of ZoomOut
	ganttBarPanel.axisStartDate = new Date(axisStartTime + diff);
	ganttBarPanel.axisEndDate = new Date(axisEndTime - diff);
	// ganttBarPanel.axisEndX = Math.round(axisEndX * zoomFactor);

	// Calculate the new "central time" in the middle of the view area
	var newCentralTime = ganttBarPanel.x2time(centralX);

	// Calculate the new scroll, so that new = old central time.
	var centralDiffTime = newCentralTime - oldCentralTime;
	var centralDiffX = centralDiffTime * axisEndX / (axisEndTime - axisStartTime);
	var newScrollX = scrollX - centralDiffX;

	scrollableEl.setScrollLeft(newScrollX);

	// Redraw before passing control back to the browser
	me.getGanttBarPanel().needsRedraw = true;

	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomIn: Finished');
    },

    /**
     * Zoom Out
     */
    onButtonZoomOut: function() {
        var me = this;
	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomOut: Starting');
	var ganttBarPanel = me.getGanttBarPanel();
	var zoomFactor = me.zoomFactor;

	var axisStartTime = ganttBarPanel.axisStartDate.getTime();
	var axisEndTime = ganttBarPanel.axisEndDate.getTime();
	var axisEndX = ganttBarPanel.axisEndX;
	var diff = (axisEndTime - axisStartTime) / zoomFactor;
	
	ganttBarPanel.axisStartDate = new Date(axisStartTime - diff);
	ganttBarPanel.axisEndDate = new Date(axisEndTime + diff);
	// ganttBarPanel.axisEndX = Math.round(axisEndX / zoomFactor);

	me.onButtonZoomCenter();					// Center the project

	// Redraw before passing control back to the browser
	me.getGanttBarPanel().needsRedraw = true;

	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomOut: Finished');
    },

    /**
     * Zoom Center
     * Set the scroll bar so that the currently selected task
     * (or the main task if no task is selected) is shown in 
     * the middle of the GanttBarPanel.
     */
    onButtonZoomCenter: function() {
        var me = this;
	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomCenter: Starting');
	var ganttBarPanel = me.getGanttBarPanel();
        var ganttTreePanel = me.getGanttTreePanel();
	var taskTreeStore = ganttTreePanel.getStore();
	
	var selectionModel = ganttTreePanel.getSelectionModel();
	var lastSelected = selectionModel.getLastSelected();

	if (!lastSelected) {					// Nothing selected - take the main project
	    var rootNode = taskTreeStore.getRootNode();
	    lastSelected = rootNode.childNodes[0];
	}

	// Calculate the "midX" X-coordinate of the middle of the current task
	var startDate = PO.Utilities.pgToDate(lastSelected.get('start_date'));
	var endDate = PO.Utilities.pgToDate(lastSelected.get('end_date'));
	var startTime = startDate.getTime();
	var endTime = endDate.getTime();
	var startX = ganttBarPanel.date2x(startTime);
	var endX = ganttBarPanel.date2x(endTime);

	// Check if the bar got outside the drawing area when zooming in
	if (startX < 0) {
	    // !!! ???
	}

	// Compare the middle of the Gantt bar with the middle of the screen
	var midX = Math.round((startX + endX) / 2);
	var ganttSize = ganttBarPanel.getSize();
	var ganttMidX = Math.round(ganttSize.width / 2);

	var scrollX = midX - ganttMidX;
	if (scrollX < 0) scrollX = 0;
	if (scrollX > (ganttBarPanel.axisEndX - 100)) scrollX = ganttBarPanel.axisEndX - 100;
	
	var scrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
	scrollableEl.setScrollLeft(scrollX);

	// Redraw before passing control back to the browser
	me.getGanttBarPanel().needsRedraw = true;

	if (me.debug) console.log('GanttEditor.controller.GanttBarPanelController.onButtonZoomCenter: Finished');
    }

});

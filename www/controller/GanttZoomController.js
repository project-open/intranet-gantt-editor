/*
 * GanttZoomController.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * Deal with zoom In/Out buttons, sizing the X axis according to the
 * project and centering the scroll bars to show the entire projects.
 * All related to the GanttBarPanel.
 */
Ext.define('GanttEditor.controller.GanttZoomController', {
    extend: 'Ext.app.Controller',
    refs: [
        {ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
        {ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],
    
    debug: false,
    senchaPreferenceStore: null,			// preferences
    zoomFactor: 5.0,	   				// Fast or slow zooming? 2.0 is fast, 10.0 is very slow

    init: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.init: Starting');
        me.control({
            '#buttonZoomIn': { click: me.onButtonZoomIn },
            '#buttonZoomOut': { click: me.onButtonZoomOut },
            '#buttonZoomCenter': { click: me.onButtonZoomCenter }
        });
        
        // Redraw GanttBars when all events are handled
        Ext.globalEvents.on("idle", this.onIdle, me)

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.init: Finished');
    },

    /**
     * Called before passing control back to the Browser.
     * Used to initiate a redraw() if necessary.
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
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomIn: Starting');
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
	me.senchaPreferenceStore.setPreference('scrollX', newScrollX);                  	// write new scrollX as a default into a persistent preference

        // Redraw before passing control back to the browser
        me.getGanttBarPanel().needsRedraw = true;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomIn: Finished');
    },

    /**
     * Zoom Out
     */
    onButtonZoomOut: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomOut: Starting');
        var ganttBarPanel = me.getGanttBarPanel();
        var zoomFactor = me.zoomFactor;

        var axisStartTime = ganttBarPanel.axisStartDate.getTime();
        var axisEndTime = ganttBarPanel.axisEndDate.getTime();
        var axisEndX = ganttBarPanel.axisEndX;
        var diff = (axisEndTime - axisStartTime) / zoomFactor;
        
        ganttBarPanel.axisStartDate = new Date(axisStartTime - diff);
        ganttBarPanel.axisEndDate = new Date(axisEndTime + diff);

        // Redraw before passing control back to the browser
        me.getGanttBarPanel().needsRedraw = true;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomOut: Finished');
    },

    /**
     * Zoom towards a task selected by the user.
     * Set the scroll bar so that the task is shown in 
     * the middle of the GanttBarPanel, but don't zoom
     * in or out.
     */
    zoomOnSelectedTask: function(selectedTask) {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomOnSelectedTask: Starting');

        var ganttBarPanel = me.getGanttBarPanel();
        var ganttTreePanel = me.getGanttTreePanel();
        var taskTreeStore = ganttTreePanel.getStore();

        // Calculate the "midX" X-coordinate of the middle of the current task
        var start_date = selectedTask.get('start_date');
        var end_date = selectedTask.get('end_date');
        if ("" == start_date || "" == end_date) return;     // Skip if there are issues with start or end_date
        
        var startDate = PO.Utilities.pgToDate(start_date);
        var endDate = PO.Utilities.pgToDate(end_date);

        var startX = ganttBarPanel.date2x(startDate);
        var endX = ganttBarPanel.date2x(endDate);
        var midX = Math.round((startX + endX) / 2);

        // Compare the middle of the Gantt bar with the middle of the screen
        var ganttSize = ganttBarPanel.getSize();
        var ganttMidX = Math.round(ganttSize.width / 2);
        
        var scrollX = midX - ganttMidX;
        if (scrollX < 0) scrollX = 0;
        if (scrollX > (ganttBarPanel.axisEndX - 100)) scrollX = ganttBarPanel.axisEndX - 100;
        
        var scrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
        scrollableEl.setScrollLeft(scrollX);
	me.senchaPreferenceStore.setPreference('scrollX', scrollX);	// write new scrollX as a default into a persistent preference

        // Redraw before passing control back to the browser
        me.getGanttBarPanel().needsRedraw = true;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomOnSelectedTask: Finished');
    },


    /**
     * Set zoom so that the entire project is visible in the 
     * visible GanttBarPanel area.
     */
    zoomOnProject: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomOnProject: Starting');

        var oneDayMiliseconds = 24 * 3600 * 1000;
        var ganttBarPanel = me.getGanttBarPanel();
        var ganttTreePanel = me.getGanttTreePanel();
        var taskTreeStore = ganttTreePanel.getStore();
        var zoomFactor = me.zoomFactor;

        // Initialize extremes for maximum calculation
        var startTime = 10000*10000*10000*10000;
        var endTime = 0;
        
        // Iterate through all children to find min & max
        var rootNode = taskTreeStore.getRootNode();
        rootNode.cascadeBy(function(model) {
            var start_date = model.get('start_date');
            if ("" != start_date) {
                var t = PO.Utilities.pgToDate(start_date).getTime();
                if (t < startTime) { startTime = t; }
            }
            var end_date = model.get('end_date');
            if ("" != end_date) {
                var t = PO.Utilities.pgToDate(end_date).getTime();
                if (t > endTime) { endTime = t; }
            }
        });

        // Error: start_date or end_date not available in the project - just ignore in this strange case
        if (endTime == 0 || startTime == 10000*10000*10000*10000) return;

        var startX = ganttBarPanel.date2x(startTime);
        var endX = ganttBarPanel.date2x(endTime);
        var midX = Math.round((startX + endX) / 2);
        var ganttSize = ganttBarPanel.getSize();
        var ganttMidX = Math.round(ganttSize.width / 2);
	var surfaceWidth = ganttBarPanel.surface.width;

	// Set axis start- and endDate so that the project fits into the ganttSize.width visible field
	var factor = 1.0 * surfaceWidth / ganttSize.width;

        ganttBarPanel.axisStartDate = new Date(startTime - (0.5 * factor) * (endTime - startTime) - oneDayMiliseconds);
        ganttBarPanel.axisEndDate =   new Date(endTime   + (0.5 * factor) * (endTime - startTime) + oneDayMiliseconds);

	var scrollX = Math.round((surfaceWidth -ganttSize.width) / 2);
        var scrollableEl = ganttBarPanel.getEl();                       // Ext.dom.Element that enables scrolling
        scrollableEl.setScrollLeft(scrollX);
	me.senchaPreferenceStore.setPreference('scrollX', scrollX);	// write new scrollX as a default into a persistent preference

        // Redraw before passing control back to the browser
        ganttBarPanel.needsRedraw = true;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomOnProject: Finished');
    },


    /**
     * Zoom Center
     * Set the scroll bar so that the currently selected task
     * (or the main task if no task is selected) is shown in 
     * the middle of the GanttBarPanel.
     */
    onButtonZoomCenter: function() {
        var startDate, endDate, startX, endX, midX;
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomCenter: Starting');

        var ganttBarPanel = me.getGanttBarPanel();
        var ganttTreePanel = me.getGanttTreePanel();
        var taskTreeStore = ganttTreePanel.getStore();
        
        // Center around a selected Gantt task.
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        if (lastSelected) {
            me.zoomOnSelectedTask(lastSelected);
            return;
        }

        me.zoomOnProject();

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomCenter: Finished');
    }


});


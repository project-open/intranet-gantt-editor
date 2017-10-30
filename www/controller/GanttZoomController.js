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
 *
 * Zoom is determined by the following variables of the GanttBarPanel
 * (defined in AbstractGanttPanel):
 * - axisStartX: Always 0, so this shouldn't be a variable, actually....
 * - axisEndX: End of the axis in pixel terms. Determines the size of the drawing surface.
 *   Increasing axixEndX has a zoom-in effect, and a scroll bar will appear if 
 *   axisEndX > ganttBarPanel.width.
 * - axisStartDate: Set to project_start_date minus a margin by default.
 * - axisEndDate: Set to project_end_date plus a margin by default.
 *   Start- and EndDate are set wider for zooming out of the project,
 *   once axisEndX = GanttParPanel.width.
 *
 * 1. Decrease the size of the surface, until the surface has the size of the GanttBarPanel.
 * 2. Set the size of the surface exactly to the size of the GanttBarPanel.
 * 3. Now start changing axisStartDate and axisEndDate in order to increase the time
 *    span shown with the surface.width pixels.
 *
 * Perform the opposed steps when zooming in.
 */
Ext.define('GanttEditor.controller.GanttZoomController', {
    extend: 'Ext.app.Controller',
    id: 'ganttZoomController',
    refs: [
        {ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
        {ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],
    
    debug: false,
    senchaPreferenceStore: null,			// preferences
    zoomFactor: 1.5,	   				// Fast or slow zooming? 2.0 is fast, 1.2 is very slow
    zoomOnEntireProjectMarginFactor: 0.2,		// Margin to leave at the left and right
    zoomOnEntireProjectMinMarginDays: 2,		// Minimum margin in days

    // ToDo: Do we need to update zooming after a resize?

    init: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.init: Starting');

        // Catch events from three zoom buttons
        me.control({
            '#buttonZoomIn': { click: me.onButtonZoomIn },
            '#buttonZoomOut': { click: me.onButtonZoomOut },
            '#buttonZoomCenter': { click: me.onButtonZoomCenter }
        });

        // Catch scroll events
        var ganttBarPanel = me.getGanttBarPanel();
        var scrollableEl = ganttBarPanel.getEl();
        scrollableEl.on({
            'scroll': me.onHorizontalScroll,
            'scope': this
        });

        // Check if there is a state stored from a previous session.
        var persistedP = me.restoreFromPreferenceStore();
        if (!persistedP) {
            // Otherwise show the entire project as a default
            me.zoomOnEntireProject();
        }

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.init: Finished');
    },


    /**
     * Set axis and scroll configuration as stored
     * in the SenchaPreferenceStore from the last session
     */
    restoreFromPreferenceStore: function() {
        var me = this;
        if (me.debug) console.log('GanttZoomController.restoreFromPreferenceStore: Started');

        var ganttBarPanel = me.getGanttBarPanel();
        var persistedP = false;
        me.senchaPreferenceStore.each(function(model) {
            var preferenceKey = model.get('preference_key');
            var preferenceValue = model.get('preference_value');
            var preferenceInt = parseInt(preferenceValue);
            switch (preferenceKey) {
            case 'scrollX': ganttBarPanel.scrollX = preferenceInt; persistedP = true; break;
            case 'axisStartTime': ganttBarPanel.axisStartDate = new Date(preferenceInt); persistedP = true; break;
            case 'axisEndTime': ganttBarPanel.axisEndDate = new Date(preferenceInt); persistedP = true; break;
            case 'axisStartX': ganttBarPanel.axisStartX = preferenceInt; persistedP = true; break;
            case 'axisEndX': ganttBarPanel.axisEndX = preferenceInt; persistedP = true; break;
            };
        });

        if (me.debug) console.log('GanttZoomController.restoreFromPreferenceStore: Finished');
        return persistedP;
    },


    /**
     * Set zoom so that the entire project fits on the surface
     * without scroll bar.
     */
    zoomOnEntireProject: function() {
        var me = this;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomEntireProject: Started');
        var ganttBarPanel = me.getGanttBarPanel();

        // Default values for axis startDate and endDate
        var oneDayMiliseconds = 24 * 3600 * 1000;
        var reportStartTime = ganttBarPanel.reportStartDate.getTime();
        var reportEndTime = ganttBarPanel.reportEndDate.getTime();
        var panelBox = ganttBarPanel.getBox();
        var panelWidth = panelBox.width;
        var panelHeight = panelBox.height;

        ganttBarPanel.axisStartX = 0;
        ganttBarPanel.axisEndX = panelWidth;
        ganttBarPanel.surface.setSize(panelWidth,panelHeight);
        var marginTime = (reportEndTime - reportStartTime) * me.zoomOnEntireProjectMarginFactor;   // space left and right
        var minMarginTime = me.zoomOnEntireProjectMinMarginDays * oneDayMiliseconds;
        if (marginTime < minMarginTime) marginTime = minMarginTime;
        ganttBarPanel.axisStartDate = new Date(reportStartTime - marginTime);
        ganttBarPanel.axisEndDate = new Date(reportEndTime + marginTime);

        // persist the changes
        me.senchaPreferenceStore.setPreference('axisStartTime', ganttBarPanel.axisStartDate.getTime());
        me.senchaPreferenceStore.setPreference('axisEndTime', ganttBarPanel.axisEndDate.getTime());
        me.senchaPreferenceStore.setPreference('axisEndX', ganttBarPanel.axisEndX);
        me.senchaPreferenceStore.setPreference('scrollX', 0);

        me.getGanttBarPanel().needsRedraw = true;                             // request a redraw

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomEntireProject: Finished');
    },

    /**
     * A user(!) has changed the horizontal scrolling by moving the scroll-bar.
     * Store the new value persistently on the server.
     * This is all we need to do, because the Browser handles the scrolling for us.
     * Debugging is disabled because there many be many events per second.
     */
    onHorizontalScroll: function(scrollEvent, htmlElement, eOpts) {
        var me = this;
        var ganttBarPanel = me.getGanttBarPanel();
        var scrollableEl = ganttBarPanel.getEl();
        var scrollX = scrollableEl.getScrollLeft();
        me.senchaPreferenceStore.setPreference('scrollX', ''+Math.round(scrollX));
    },

    /**
     * Zoom In - The user has pressed the (+) button.
     */
    onButtonZoomIn: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomIn: Starting');
        var ganttBarPanel = me.getGanttBarPanel();

        var oneDayMiliseconds = 24 * 3600 * 1000;
        var panelBox = ganttBarPanel.getBox();
        var panelWidth = panelBox.width;

        // Calculate the duration of the diagram time axix
        var reportStartTime = ganttBarPanel.reportStartDate.getTime();
        var reportEndTime = ganttBarPanel.reportEndDate.getTime();
        var marginTime = (reportEndTime - reportStartTime) * me.zoomOnEntireProjectMarginFactor;      // space at the left and right
        var minMarginTime = me.zoomOnEntireProjectMinMarginDays * oneDayMiliseconds;
        if (marginTime < minMarginTime) marginTime = minMarginTime;
        reportStartTime = reportStartTime - marginTime;
        reportEndTime = reportEndTime + marginTime;
        var reportDurationTime = reportEndTime - reportStartTime;

        // Calculate the duration of the Gantt axis in current zoom state
        var ganttStartTime = ganttBarPanel.axisStartDate.getTime();
        var ganttEndTime = ganttBarPanel.axisEndDate.getTime();
        var ganttDurationTime = ganttEndTime - ganttStartTime;
        var diffDays = Math.round(ganttDurationTime / oneDayMiliseconds / 6.0);
        if (diffDays <= 1) diffDays = 1;
        ganttStartTime = ganttStartTime + diffDays * oneDayMiliseconds;
        ganttEndTime = ganttEndTime - diffDays * oneDayMiliseconds;

        // Check if we are zoomed out in terms of time beyond the project duration.
        // In this case we will narrow start- and endTime:
        if (ganttDurationTime > reportDurationTime) {
            // Undoing 3rd level of zoom - reduce the axisStartDate and axisEndDate
            ganttBarPanel.axisStartDate = new Date(ganttStartTime);
            ganttBarPanel.axisEndDate = new Date(ganttEndTime);
            var newGanttDurationTime = ganttEndTime - ganttStartTime;
        } else {
            // Undoing 1. level of zoom
            ganttBarPanel.axisEndX = me.zoomFactor * ganttBarPanel.axisEndX;
            me.senchaPreferenceStore.setPreference('axisEndX', ganttBarPanel.axisEndX);        // Persist the new zoom parameters
        }

        // Unbalanced? Just zoom on the entire project then...
        if (ganttStartTime < reportStartTime || ganttEndTime > reportEndTime) {
            // me.zoomOnEntireProject();                                   // center and fit zoom.
        }

        me.getGanttBarPanel().needsRedraw = true;

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomIn: Finished');
    },

    /**
     * Zoom Out - The user has pressed the (-) button.
     */
    onButtonZoomOut: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomOut: Starting');
        var ganttBarPanel = me.getGanttBarPanel();

        var panelBox = ganttBarPanel.getBox();
        var panelWidth = panelBox.width;

        // This is the check for the 3. zoom phase when we already reduced the
        // size of the surface: The user wants to zoom out beyond the duration 
        // of the project, so we have to change the axis start- and end-dates:
        var zoomingBeyondSurface = false;
        if (ganttBarPanel.axisEndX <= panelWidth) {
            var startTime = ganttBarPanel.axisStartDate.getTime();
            var endTime = ganttBarPanel.axisEndDate.getTime();
            var diffDays = Math.round((endTime - startTime) / 24.0 / 3600.0 / 1000.0 / 3.0);
            if (diffDays <= 1) diffDays = 1;
            startTime = startTime - diffDays * 24.0 * 3600 * 1000;
            endTime = endTime + diffDays * 24.0 * 3600 * 1000;
            ganttBarPanel.axisStartDate = new Date(startTime);
            ganttBarPanel.axisEndDate = new Date(endTime);
            zoomingBeyondSurface = true;
        }

        // 1. level of zooming - try reducing the size of the surface area 
        var endX = ganttBarPanel.axisEndX / me.zoomFactor;

        // 2. level of zooming - we just reached the limit of the surface size.
        if (endX < panelWidth) {
            endX = panelWidth;
            // center the project
            if (!zoomingBeyondSurface) {
                me.zoomOnEntireProject();
            }
        }

        // Set the size of the axis and as a result the size of the drawing surface.
        ganttBarPanel.axisEndX = endX;
        me.getGanttBarPanel().needsRedraw = true;
        me.senchaPreferenceStore.setPreference('axisEndX', ganttBarPanel.axisEndX);        // Persist the new zoom parameters

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

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.zoomOnSelectedTask: Finished');
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

        var ganttTreePanel = me.getGanttTreePanel();
        
        // Is a task selected? Otherwise center around the entire project
        var selectionModel = ganttTreePanel.getSelectionModel();
        var lastSelected = selectionModel.getLastSelected();
        if (lastSelected) {
            me.zoomOnSelectedTask(lastSelected);
        } else {
            me.zoomOnEntireProject();
        }

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onButtonZoomCenter: Finished');
    },


    /**
      * Somebody pressed the "Fullscreen" button...
      * This function is called by the ResizeController.
      */
    onSwitchToFullScreen: function () {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onSwitchToFullScreen: Starting');

        var ganttBarPanel = me.getGanttBarPanel();
        var panelBox = ganttBarPanel.getBox();
        var panelWidth = panelBox.width;
        var panelHeight = panelBox.height;

        var surfaceWidth = ganttBarPanel.axisEndX;

        if (surfaceWidth < panelWidth) {
            ganttBarPanel.axisEndX = panelWidth;
            ganttBarPanel.surface.setSize(panelWidth,panelHeight);

            // persist the changes
            me.senchaPreferenceStore.setPreference('axisEndX', ganttBarPanel.axisEndX);
            me.senchaPreferenceStore.setPreference('scrollX', 0);

            ganttBarPanel.needsRedraw = true;                             // request a redraw
        }

        if (me.debug) console.log('GanttEditor.controller.GanttZoomController.onSwitchToFullScreen: Finished');
    }
});


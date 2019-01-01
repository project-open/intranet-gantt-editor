/*
 * GanttConfigController.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * Deal with actions of the configuration menu
 */
Ext.define('GanttEditor.controller.GanttConfigController', {
    extend: 'Ext.app.Controller',
    id: 'ganttConfigController',
    refs: [
        {ref: 'ganttBarPanel', selector: '#ganttBarPanel'},
        {ref: 'ganttTreePanel', selector: '#ganttTreePanel'}
    ],
    
    debug: false,
    senchaPreferenceStore: null,			// preferences
    configMenu: null,
    ganttBarPanel: null,

    init: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttConfigController.init: Starting');

	me.configMenu.on({
	    'click': me.onConfigClick,
	    'scope': this
	});

        if (me.debug) console.log('GanttEditor.controller.GanttConfigController.init: Finished');
    },

    onConfigClick: function(menu, item, e, eOpts) {
	var me = this;
        if (me.debug) console.log('GanttEditor.controller.GanttConfigController.onConfigClick: Starting');
	switch (item.id) {
	case 'config_menu_show_project_findocs': 
	    
	    // Redraw immediately
	    me.ganttBarPanel.needsRedraw = true;
	    me.ganttBarPanel.redraw();
	    break;
	}
        if (me.debug) console.log('GanttEditor.controller.GanttConfigController.onConfigClick: Finished');
    }
});


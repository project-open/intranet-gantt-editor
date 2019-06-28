/*
 * GanttDependencyPropertyPanel.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/*
 * GanttTaskPropertyPanel.js
 *
 * Copyright (c) 2011 - 2014 ]project-open[ Business Solutions, S.L.
 * This file may be used under the terms of the GNU General Public
 * License version 3.0 or alternatively unter the terms of the ]po[
 * FL or CL license as specified in www.project-open.com/en/license.
 */

/**
 * A free floating singleton TabPanel with several elements 
 * allowing to edit the details of a single task.
 */
Ext.define('GanttEditor.view.GanttDependencyPropertyPanel', {
    extend:                             'Ext.Window',
    id:                                 'ganttDependencyPropertyPanel',
    alias:                              'ganttDependencyPropertyPanel',

    title: 'Dependency Properties',
    id: 'ganttDependencyPropertyPanel',
    senchaPreferenceStore: null,

    debug: false,
    width: 500,
    height: 420,

    closable: true,
    closeAction: 'hide',
    resizable: true,
    modal: false,
    layout: 'fit',

    dependencyModel: null,								// Set by setValue() before show()
    
    initComponent: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.initialize: Starting');
        this.callParent(arguments);
        
        var dependencyPropertyFormGeneral = Ext.create('Ext.form.Panel', {
            title: 'General',
            id: 'dependencyPropertyFormGeneral',
            layout: 'anchor',
            fieldDefaults: {
                labelAlign: 'right',
                labelWidth: 90,
                msgTarget: 'qtip',
                margins: '5 5 5 5',
            },
            items: [{
                xtype: 'fieldset',
                title: 'General',
                defaultType: 'textfield',
                layout: 'anchor',
                items: [{
                    xtype: 'numberfield',
                    fieldLabel: 'Lag',
                    name: 'diff',
                    width: 200,
                    value: '0',
                    allowBlank: true
                }, {
		    xtype: 'combobox',
                    fieldLabel: 'Lag Format',
                    name: 'diff_format_id',
                    displayField: 'category',
                    valueField: 'id',
                    queryMode: 'local',
		    typeAhead: true,
                    emptyText: 'Lag Format',
                    width: 250,
 		    matchFieldWidth: false,
		    store: Ext.create('Ext.data.Store', {
			fields: ['id', 'category'],
			data : [
                            {id: 9803, category: 'Month'},
                            {id: 9804, category: 'e-Month'},
                            {id: 9805, category: 'Hour'},
                            {id: 9806, category: 'e-Hour'},
                            {id: 9807, category: 'Day'},
                            {id: 9808, category: 'e-Day'},
                            {id: 9809, category: 'Week'},
                            {id: 9810, category: 'e-Week'},
                            {id: 9811, category: 'mo'},
                            {id: 9812, category: 'emo'},
                            {id: 9819, category: 'Percent'},
                            {id: 9820, category: 'e-Percent'},
                            {id: 9835, category: 'm?'},
                            {id: 9836, category: 'em?'},
                            {id: 9837, category: 'h?'},
                            {id: 9838, category: 'eh?'},
                            {id: 9839, category: 'd?'},
                            {id: 9840, category: 'ed?'},
                            {id: 9841, category: 'w?'},
                            {id: 9842, category: 'ew?'},
                            {id: 9843, category: 'mo?'},
                            {id: 9844, category: 'emo?'},
                            {id: 9851, category: 'Percent?'},
                            {id: 9852, category: 'e-Percent?'}
			]
		    }),
                    allowBlank: false,
                    forceSelection: true
                }, {
		    xtype: 'combobox',
                    fieldLabel: 'Dependency Type',
                    name: 'type_id',
                    displayField: 'category',
                    valueField: 'id',
                    queryMode: 'local',
		    typeAhead: true,
                    emptyText: 'Dependency Type',
                    width: 250,
 		    matchFieldWidth: false,
		    store: Ext.create('Ext.data.Store', {
			fields: ['id', 'category'],
			data : [
			    {id: 9660, category: "Finish-to-Finish"},
			    {id: 9662, category: "Finish-to-Start"},
			    {id: 9664, category: "Start-to-Finish"},
			    {id: 9666, category: "Start-to-Start"}
			]
		    }),
                    allowBlank: false,
                    forceSelection: true
                }]
            }]
        });

        var dependencyPropertyTabpanel = Ext.create("Ext.tab.Panel", {
            id: 'dependencyPropertyTabpanel',
            border: false,
            items: [
                dependencyPropertyFormGeneral
            ],
            buttons: [{
                text: 'OK',
                scope: me,
                handler: me.onButtonOK
            }, {
                text: 'Delete',
                scope: me,
                handler: me.onButtonDelete
            }, {
                text: 'Cancel',
                scope: me,
                handler: me.onButtonCancel
            }]    
        });
        me.add(dependencyPropertyTabpanel);

        // store panels in the main object
        me.dependencyPropertyFormGeneral = dependencyPropertyFormGeneral;
        me.dependencyPropertyTabpanel = dependencyPropertyTabpanel;

        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.initialize: Finished');
    },


    /**
     * Get the format factor to convert dependency.diff (in seconds) to the format (for example: week)
     */
    dependencyFormatFactor: function(format_id) {

        var format_factor = 1.0;

        // Format the "diff" according to the most frequent formats
        // LagFormat can be: 3=m, 4=em, 5=h, 6=eh, 7=d, 8=ed, 9=w, 10=ew, 
        // 11=mo, 12=emo, 19=%, 20=e%, 35=m?, 36=em?, 37=h?, 38=eh?, 39=d?, 
        // 40=ed?, 41=w?, 42=ew?, 43=mo?, 44=emo?, 51=%? and 52=e%?
        switch (format_id) {
        case 9803: format_factor = 30.0 * 8.0 * 3600.0; break;		// m=month, has fixed 30 days of 8 hours each at the moment
        case 9804: format_factor = 30.0 * 8.0 * 3600.0; break;		// em=
        case 9805: format_factor = 3600.0; break;			// h=hour
        case 9806: format_factor = 1.0; break;			        // eh=
        case 9807: format_factor = 8.0 * 3600.0; break;			// d=day
        case 9808: format_factor = 8.0 * 3600.0; break;			// ed=
        case 9809: format_factor = 5.0 * 8.0 * 3600.0; break;		// w=week, has 5 days
        case 9810: format_factor = 1.0; break;				// ew=
        case 9811: format_factor = 30.0 * 8.0 * 3600.0; break;		// mo=month?
        case 9812: format_factor = 30.0 * 8.0 * 3600.0; break;		// emo
        case 9819: format_factor = 1.0; break;				// %=Percent
        case 9820: format_factor = 1.0; break;				// e%=
        case 9835: format_factor = 1.0; break;				// e%=
        case 9836: format_factor = 1.0; break;				// e%=
        case 9837: format_factor = 1.0; break;				// e%=
        case 9838: format_factor = 1.0; break;				// e%=
        case 9839: format_factor = 1.0; break;				// e%=
        case 9840: format_factor = 1.0; break;				// e%=
        case 9841: format_factor = 1.0; break;				// e%=
        case 9842: format_factor = 1.0; break;				// e%=
        case 9843: format_factor = 1.0; break;				// e%=
        case 9844: format_factor = 1.0; break;				// e%=
        case 9851: format_factor = 1.0; break;				// e%=
        case 9852: format_factor = 1.0; break;				// e%=
        default: alert('GanttDependencyPropertyPanel.setValue: Found invalid diff_format_id='+format_id);
        }

        return format_factor;
    },

    /**
     * Save the modified form values into the model.
     */
    onButtonOK: function(button, event) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.onButtonOK');

        var fields = me.dependencyPropertyFormGeneral.getValues(false, true, true, true);	// get all fields into object
        var dep = me.dependencyModel;

        dep.type_id = fields.type_id;
        dep.diff_format_id = fields.diff_format_id;

        
        var formatFactor = me.dependencyFormatFactor(fields.diff_format_id);  // 8 hours per day * 3600 seconds per hour...
        dep.diff = fields.diff * formatFactor;


        // We need to force re-scheduling
        me.ganttSchedulingController.schedule();
        me.ganttBarPanel.needsRedraw = true;

        me.hide();									// hide the DependencyProperty panel
    },

    /**
     * Delete the dependency model.
     */
    onButtonDelete: function(button, event) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.onButtonDelete');

        // ToDo: Delete dep
        var dep = me.dependencyModel;
        var predId = dep.pred_id;
        var succModel = me.succProjectModel;                                             // The successor activity that owns the dependency

        // Remove dependency model from succModel
        var predecessors = succModel.get('predecessors');
        for (i = 0; i < predecessors.length; i++) {
            var el = predecessors[i];
            if (el.pred_id == predId) {
                predecessors.splice(i,1);
            }
        }
        succModel.set('predecessors',predecessors);
        

        // We need to force re-scheduling
        me.ganttSchedulingController.schedule();
        me.ganttBarPanel.needsRedraw = true;

        me.hide();									// hide the DependencyProperty panel
    },

    /**
     * Simply hide the windows.
     * This automatically discards any changes.
     */
    onButtonCancel: function(button, event) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.onButtonCancel');
        me.hide();									// hide the DependencyProperty panel
    },

    setActiveTab: function(tab) {
        var me = this;
        me.dependencyPropertyTabpanel.setActiveTab(tab);
    },

    /**
     * Try to hide the list of tabs and the outer frame
     */
    hideTabs: function() {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.hideTabs: Starting');
        var tabPanel = me.dependencyPropertyTabpanel;
        var tabBar = tabPanel.tabBar;
        tabBar.hide();
    },

    /**
     * Show the properties of the specified dependency model.
     * Write changes back to the dependency immediately (at the moment).
     */
    setValue: function(dependency, succProjectModel) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Starting');

        // Load the data into the various forms
        var form = me.dependencyPropertyFormGeneral.getForm();
        form.setValues(dependency);

        var diff_format_id = dependency.diff_format_id;
        var formatFactor = me.dependencyFormatFactor(diff_format_id);  // 8 hours per day * 3600 seconds per hour...

        var diff = dependency.diff;
        var correctedDiff = Math.round(100.0 * (diff / formatFactor)) / 100.0;
        var diffField = form.findField('diff');
        diffField.setValue(correctedDiff);

        me.dependencyModel = dependency;								// Save the model for reference
        me.succProjectModel = succProjectModel;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Finished');
    }
}); 


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

        // New store for keeping assignment data, setValue() adds the data.
        var dependencyAssignmentStore = Ext.create('Ext.data.Store', {
            id: 'dependencyAssignmentStore',
            model: 'PO.model.gantt.GanttAssignmentModel'
        });

        var dependencyPropertyFormNotes = Ext.create('Ext.form.Panel', {
            title: 'Notes',
            id: 'dependencyPropertyFormNotes',
            layout: 'fit',
            items: [{
                xtype: 'htmleditor',
                enableColors: false,
                enableAlignments: true,
                name: 'description'
            }]
        });
        
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
                    fieldLabel: 'Name',
                    name: 'project_name',
                    width: 450,
                    allowBlank: false
                }, {
                    xtype: 'numberfield',
                    fieldLabel: 'Delay',
                    name: 'planned_units',
                    width: 140,
                    value: '0',
                    minValue: 0,
                    allowBlank: true
                }, {
		    xtype: 'combobox',
                    fieldLabel: 'Dependency Type',
                    name: 'dependeny_type_id',
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
			    {id: "9660", category: "Finish-to-Finish"},
			    {id: "9662", category: "Finish-to-Start"},
			    {id: "9664", category: "Start-to-Finish"},
			    {id: "9666", category: "Start-to-Start"}
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
                dependencyPropertyFormGeneral,
                dependencyPropertyFormNotes
            ],
            buttons: [{
                text: 'OK',
                scope: me,
                handler: me.onButtonOK
            }, {
                text: 'Cancel',
                scope: me,
                handler: me.onButtonCancel
            }]    
        });
        me.add(dependencyPropertyTabpanel);

        // store panels in the main object
        me.dependencyPropertyFormGeneral = dependencyPropertyFormGeneral;
        me.dependencyPropertyFormNotes = dependencyPropertyFormNotes;
        me.dependencyPropertyTabpanel = dependencyPropertyTabpanel;

        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.initialize: Finished');
    },

    /**
     * Save the modified form values into the model.
     */
    onButtonOK: function(button, event) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.onButtonOK');

        // Write timestamp to make sure that data are modified and redrawn.
        me.dependencyModel.set('last_modified', Ext.Date.format(new Date(), 'Y-m-d H:i:s'));
        
        // ---------------------------------------------------------------
        // "General" form panel with start- and end date, %done, work etc.
        var fields = me.dependencyPropertyFormGeneral.getValues(false, true, true, true);	// get all fields into object

        var oldStartDate = me.dependencyModel.get('start_date');
        var oldEndDate = me.dependencyModel.get('end_date');
        var newStartDate = fields['start_date'];
        var newEndDate = fields['end_date'];
        if (oldStartDate.substring(0,10) == newStartDate) { fields['start_date'] = oldStartDate; }	// start has no time
        if (oldEndDate.substring(0,10) == newEndDate) { fields['end_date'] = oldEndDate; }	 	// start has no time

        var plannedUnits = fields['planned_units'];
        if (undefined == plannedUnits) { plannedUnits = 0; }

        // fix boolean vs. 't'/'f' checkbox for milestone_p
        switch (fields['milestone_p']) {
        case true: 
            fields['milestone_p'] = 't';						// use 't' and 'f', not true and false!
            fields['iconCls'] = 'icon-milestone';					// special icon for milestones
            fields['end_date'] = fields['start_date'];					// Milestones have end_date = start_date
            fields['planned_units'] = "0";             			                // Milestones don't have planned_units
            break;
        default: 
            fields['milestone_p'] = 'f'; 
            fields['iconCls'] = 'icon-dependency';						// special icon for non-milestones
            fields['planned_units'] = ""+plannedUnits;              			// Convert the numberfield integer to string used in model.
            break;	      								// '' is database "null" value in ]po[
        }

        // fix boolean vs. 't'/'f' checkbox for effort_driven_p
        switch (fields['effort_driven_p']) {
        case true: 
            fields['effort_driven_p'] = 't';						// use 't' and 'f', not true and false!
            break;
        default: 
            fields['effort_driven_p'] = 'f'; 
            break;
        }

        me.dependencyModel.set(fields); 							// write all fields into model
        
        // Notes form
        fields = me.dependencyPropertyFormNotes.getValues(false, true, true, true);
        me.dependencyModel.set(fields);

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
    setValue: function(dependency) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Starting');
        var projectMemberStore = Ext.StoreManager.get('projectMemberStore');

        // Default values for dependency if not defined yet by ]po[
        // ToDo: Unify with default values in onButtonAdd
        if ("" == dependency.get('planned_units')) { dependency.set('planned_units', '0'); }
        if ("" == dependency.get('uom_id')) { dependency.set('uom_id', ""+default_uom_id); } 		// "Day" as UoM
        if ("" == dependency.get('material_id')) { dependency.set('material_id', ""+default_material_id); }	// "Default" material
        if ("" == dependency.get('priority')) { dependency.set('priority', '500'); }
        if ("" == dependency.get('start_date')) { dependency.set('start_date',  Ext.Date.format(new Date(), 'Y-m-d')); }
        if ("" == dependency.get('end_date')) { dependency.set('end_date',  Ext.Date.format(new Date(), 'Y-m-d')); }
        if ("" == dependency.get('percent_completed')) { dependency.set('percent_completed', '0'); }

        // Load the data into the various forms
        me.dependencyPropertyFormGeneral.getForm().loadRecord(dependency);
        me.dependencyPropertyFormNotes.getForm().loadRecord(dependency);

        // Load assignment information into the assignmentStore
        me.dependencyAssignmentStore.removeAll();
        var assignments = dependency.get('assignees');
        if (assignments.constructor !== Array) { assignments = []; }         		// Newly created dependency...
        assignments.forEach(function(v) {
            var userId = ""+v.user_id;
            var userModel = projectMemberStore.getById(userId);
            if (!userModel) { return; }                                      		// User not set in assignment row
            var assigModel = new PO.model.gantt.GanttAssignmentModel(userModel.data);
            assigModel.set('percent', v.percent);
            me.dependencyAssignmentStore.add(assigModel);
        });

        me.dependencyModel = dependency;								// Save the model for reference
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Finished');
    }
}); 


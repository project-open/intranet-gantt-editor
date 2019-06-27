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
                    fieldLabel: 'Delay',
                    name: 'diff',
                    width: 140,
                    value: '0',
                    allowBlank: true
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
     * Save the modified form values into the model.
     */
    onButtonOK: function(button, event) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.onButtonOK');

        var fields = me.dependencyPropertyFormGeneral.getValues(false, true, true, true);	// get all fields into object
        var dep = me.dependencyModel;

        dep.type_id = fields.type_id;
        dep.diff = fields.diff;

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
    setValue: function(dependency) {
        var me = this;
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Starting');

        // Load the data into the various forms
        var form = me.dependencyPropertyFormGeneral.getForm();
        form.setValues(dependency);

        // var typeField = form.findField('type_id');
        // typeField.setValue(''+dependency.type_id);

        me.dependencyModel = dependency;								// Save the model for reference
        if (me.debug) console.log('GanttEditor.view.GanttDependencyPropertyPanel.setValue: Finished');
    }
}); 


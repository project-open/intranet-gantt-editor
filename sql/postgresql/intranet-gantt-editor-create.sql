-- /packages/intranet-gantt-editor/sql/postgresql/intranet-gantt-editor-create.sql
--
-- Copyright (c) 2010 ]project-open[
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com

-- ------------------------------------------------------------
-- Gantt Editor Portlet
-- ------------------------------------------------------------

SELECT im_component_plugin__new (
	null,					-- plugin_id
	'im_component_plugin',			-- object_type
	now(),					-- creation_date
	null,					-- creation_user
	null,					-- creation_ip
	null,					-- context_id
	'Gantt Editor',				-- plugin_name
	'intranet-gantt-editor',		-- package_name
	'top',					-- location
	'/intranet/projects/view',		-- page_url
	null,					-- view_name
	10,					-- sort_order
	'gantt_editor_portlet -project_id $project_id'
);

SELECT acs_permission__grant_permission(
        (select plugin_id from im_component_plugins where plugin_name = 'Gantt Editor' and package_name = 'intranet-gantt-editor'),
        (select group_id from groups where group_name = 'Employees'),
        'read'
);


---------------------------------------------------------
-- REST Data-Sources
--
-- These reports are portfolio-planner specific, so we do
-- not have to add them to sencha-core.
---------------------------------------------------------

-- List all intra-project dependencies on the server
--
SELECT im_report_new (
	'REST Intra-Project Task Dependencies',				-- report_name
	'rest_intra_project_task_dependencies',				-- report_code
	'sencha-core',							-- package_key
	220,								-- report_sort_order
	(select menu_id from im_menus where label = 'reporting-rest'),	-- parent_menu_id
	''
);

update im_reports set 
       report_description = 'Returns the list of intra-project dependencies',
       report_sql = '
select	d.dependency_id as id,
	d.*,
	main_project.project_id as main_project_id_one,
	main_project.project_name as main_project_name_one,

	p_one.project_id as task_one_id,
	p_one.project_name as task_one_name,
	p_one.start_date as task_one_start_date,
	p_one.end_date as task_one_end_date,

	p_two.project_id as task_two_id,
	p_two.project_name as task_two_name,
	p_two.start_date as task_two_start_date,
	p_two.end_date as task_two_end_date

from	im_timesheet_task_dependencies d,
	im_projects p_one,
	im_projects p_two,
	im_projects main_project

where	main_project.project_id = %main_project_id% and
	p_one.project_id = d.task_id_one and
	p_two.project_id = d.task_id_two and
	p_one.tree_sortkey betweeen main_project.tree_sortkey and tree_right(main_project.tree_sortkey) and
	p_two.tree_sortkey betweeen main_project.tree_sortkey and tree_right(main_project.tree_sortkey)
order by p_one.tree_sortkey, p_two.tree_sortkey
'       
where report_code = 'rest_intra_project_task_dependencies';

-- Relatively permissive
SELECT acs_permission__grant_permission(
	(select menu_id from im_menus where label = 'rest_intra_project_task_dependencies'),
	(select group_id from groups where group_name = 'Employees'),
	'read'
);


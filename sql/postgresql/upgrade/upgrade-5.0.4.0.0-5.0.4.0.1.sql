-- upgrade-5.0.4.0.0-5.0.4.0.1.sql

SELECT acs_log__debug('/packages/intranet-gantt-editor/sql/postgresql/upgrade/upgrade-5.0.4.0.0-5.0.4.0.1.sql', '');


update im_reports set 
       report_description = 'Lists absences and assignments to other projects of the members of a project',
       report_sql = '
       		-- Individual absences from im_user_absences (by user)
		select	t.*,
			im_name_from_user_id(user_id) as user_name,
			acs_object__name(context_id) as context
		from	(
			select
				a.absence_id as object_id,
				''im_user_absence'' as object_type,
				a.owner_id as user_id,
				a.start_date,
				a.end_date,
				100 as percentage,
				a.absence_name as name,
				0 as context_id
			from	im_user_absences a
			where	a.owner_id in (
					select distinct
						object_id_two
					from	acs_rels,
						im_projects sub_p,
						im_projects main_p
					where	object_id_one = sub_p.project_id and
						sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
						main_p.project_id = %main_project_id%
				) and
				a.end_date >= (select start_date from im_projects where project_id = %main_project_id%) and
				a.start_date <= (select end_date from im_projects where project_id = %main_project_id%)
		UNION
			-- Group absences such as bank holidays
			select
				a.absence_id as object_id,
				''im_user_absence'' as object_type,
				gei.element_id as user_id,
				a.start_date,
				a.end_date,
				100 as percentage,
				a.absence_name as name,
				0 as context_id
			from	im_user_absences a,
				group_element_index gei
			where	a.group_id = gei.group_id and
				gei.element_id in (
					select distinct
						object_id_two
					from	acs_rels,
						im_projects sub_p,
						im_projects main_p
					where	object_id_one = sub_p.project_id and
						sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
						main_p.project_id = %main_project_id%
				) and
				a.end_date >= (select start_date from im_projects where project_id = %main_project_id%) and
				a.start_date <= (select end_date from im_projects where project_id = %main_project_id%)
		UNION
			-- Assignments to other projects
			select	p.project_id as object_id,
				''im_project'' as object_type,
				pe.person_id as user_id,
				p.start_date,
				p.end_date,
				coalesce(bom.percentage, 0) as percentage,
				p.project_name as name,
				(select main_p.project_id from im_projects main_p 
				where main_p.tree_sortkey = tree_root_key(p.tree_sortkey)
				) as context_id
			from	persons pe,
				im_projects p,
				im_projects super_p,
				acs_rels r,
				im_biz_object_members bom
			where
				super_p.parent_id is null and
				p.parent_id is not null and		-- Ignore assignments on a main project level
				p.tree_sortkey between super_p.tree_sortkey and tree_right(super_p.tree_sortkey) and
				super_p.project_status_id in (select * from im_sub_categories(76)) and
				p.project_status_id in (select * from im_sub_categories(76)) and

				r.rel_id = bom.rel_id and
				r.object_id_one = p.project_id and
				r.object_id_two = pe.person_id and
				pe.person_id in (
					-- Only report about persons assigned in main_p
					select distinct
						object_id_two
					from	acs_rels,
						im_projects sub_p,
						im_projects main_p
					where	object_id_one = sub_p.project_id and
						sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
						main_p.project_id = %main_project_id%
				) and p.project_id not in (
					-- Exclude assignments within main_p (handled in JavaScript)
					select	sub_p.project_id
					from	im_projects sub_p,
						im_projects main_p
					where	sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey) and
						main_p.project_id = %main_project_id%
				) and
				p.end_date >= (select start_date from im_projects where project_id = %main_project_id%) and
				p.start_date <= (select end_date from im_projects where project_id = %main_project_id%)

			) t
		where	percentage > 0.0
		order by
			object_type,
			object_id,
			user_id
'       
where report_code = 'rest_project_member_assignments_absences';


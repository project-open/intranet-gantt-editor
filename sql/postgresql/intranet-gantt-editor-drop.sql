-- /packages/intranet-gantt-editor/sql/postgresql/intranet-gantt-editor-drop.sql
--
-- Copyright (c) 2010 ]project-open[
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com


select im_component_plugin__del_module('intranet-gantt-editor');
select im_menu__del_module('intranet-gantt-editor');


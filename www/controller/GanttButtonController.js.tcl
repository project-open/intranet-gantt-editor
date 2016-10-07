# Determine system parameters for error reporting

ns_set cput [ns_conn outputheaders] "Access-Control-Allow-Origin" "*"


set error_url [im_url_with_query]
set error_location "[ns_info address] on [ns_info platform]"
set report_url [parameter::get -package_id [im_package_core_id] -parameter "ErrorReportURL" -default ""]
set error_type "default"
set system_url [parameter::get -package_id [ad_acs_kernel_id] -parameter SystemURL -default ""]
set first_names "undefined"
set last_name "undefined"
set email "undefined"
set username "undefined"
db_0or1row user_info "select * from cc_users where user_id=[ad_get_user_id]"
set publisher_name [parameter::get -package_id [ad_acs_kernel_id] -parameter PublisherName -default ""]
set package_versions [db_list package_versions "select v.package_key||':'||v.version_name from (select max(version_id) as version_id, package_key from apm_package_versions group by package_key) m, apm_package_versions v where m.version_id = v.version_id"]
set system_id [im_system_id]
set hardware_id [im_hardware_id]

set platform $::tcl_platform(platform)
set os $::tcl_platform(os)
set os_version $::tcl_platform(osVersion)


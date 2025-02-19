#!/bin/bash
source "$(dirname "${BASH_SOURCE}")/../../hack/lib/init.sh"
trap os::test::junit::reconcile_output EXIT

# Cleanup cluster resources created by this test
(
  set +e
  oc delete all,templates --all
  oc delete template/ruby-helloworld-sample -n openshift
  oc delete project test-template-project
  oc delete user someval someval=moreval someval=moreval2 someval=moreval3
  exit 0
) &>/dev/null


os::test::junit::declare_suite_start "cmd/templates"
# This test validates template commands

os::test::junit::declare_suite_start "cmd/templates/basic"
os::cmd::expect_success 'oc get templates'
os::cmd::expect_success 'oc create -f ${TEST_DATA}/application-template-dockerbuild.json'
os::cmd::expect_success 'oc get templates'
os::cmd::expect_success 'oc get templates ruby-helloworld-sample'
os::cmd::expect_success 'oc get template ruby-helloworld-sample -o json | oc process -f -'
os::cmd::expect_success 'oc process ruby-helloworld-sample'
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o template --template "{{.kind}}"'    "List"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o go-template --template "{{.kind}}"' "List"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o go-template={{.kind}}'              "List"
os::cmd::expect_success 'oc process ruby-helloworld-sample -o go-template-file=/dev/null'
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o jsonpath --template "{.kind}"' "List"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o jsonpath={.kind}'              "List"
os::cmd::expect_success 'oc process ruby-helloworld-sample -o jsonpath-file=/dev/null'
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o describe' "ruby-27-centos7"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o json'     "ruby-27-centos7"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o yaml'     "ruby-27-centos7"
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -o name'     "ruby-27-centos7"
os::cmd::expect_success_and_text 'oc describe templates ruby-helloworld-sample' "BuildConfig.*ruby-sample-build"
os::cmd::expect_success 'oc delete templates ruby-helloworld-sample'
os::cmd::expect_success 'oc get templates'
# TODO: create directly from template
echo "templates: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/templates/config"
guestbook_template="${TEST_DATA}/templates/guestbook.json"
os::cmd::expect_success "oc process -f '${guestbook_template}' -l app=guestbook | oc create -f -"
os::cmd::expect_success_and_text 'oc status' 'frontend-service'
echo "template+config: ok"

os::test::junit::declare_suite_start "cmd/templates/local-config"
# Processes the template locally
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --local -l app=guestbook -o yaml" "app: guestbook"
# Processes the template locally and get the same output in YAML
new="$(mktemp -d)"
os::cmd::expect_success 'oc process -f "${guestbook_template}" --local -l app=guestbook -o yaml ADMIN_USERNAME=au ADMIN_PASSWORD=ap REDIS_PASSWORD=rp > "${new}/localtemplate"'
os::cmd::expect_success 'oc process -f "${guestbook_template}" -l app=guestbook -o yaml ADMIN_USERNAME=au ADMIN_PASSWORD=ap REDIS_PASSWORD=rp > "${new}/remotetemplate"'
os::cmd::expect_success 'diff "${new}/localtemplate" "${new}/remotetemplate"'
# Does not even try to hit the server
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --local -l app=guestbook -o yaml --server 0.0.0.0:1" "app: guestbook"
echo "template+config+local: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/templates/parameters"
guestbook_params="${TEST_DATA}/templates/guestbook.env"
# Individually specified parameter values are honored
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' -p ADMIN_USERNAME=myuser -p ADMIN_PASSWORD=mypassword" '"myuser"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' -p ADMIN_USERNAME=myuser -p ADMIN_PASSWORD=mypassword" '"mypassword"'
# Argument values are honored
os::cmd::expect_success_and_text "oc process ADMIN_USERNAME=myuser ADMIN_PASSWORD=mypassword -f '${guestbook_template}'"       '"myuser"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' ADMIN_USERNAME=myuser ADMIN_PASSWORD=mypassword"       '"mypassword"'
# Argument values with commas are honored
os::cmd::expect_success 'oc create -f ${TEST_DATA}/application-template-stibuild.json'
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample MYSQL_USER=myself MYSQL_PASSWORD=my,1%pa=s'        '"myself"'
os::cmd::expect_success_and_text 'oc process MYSQL_USER=myself MYSQL_PASSWORD=my,1%pa=s ruby-helloworld-sample'        '"my,1%pa=s"'
os::cmd::expect_success_and_text 'oc process ruby-helloworld-sample -p MYSQL_USER=myself -p MYSQL_PASSWORD=my,1%pa=s'  '"myself"'
os::cmd::expect_success_and_text 'oc process -p MYSQL_USER=myself -p MYSQL_PASSWORD=my,1%pa=s ruby-helloworld-sample'  '"my,1%pa=s"'
# Argument values can be read from file
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}'" '"root"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}'" '"adminpass"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}'" '"redispass"'
# Argument values can be read from stdin
os::cmd::expect_success_and_text "cat '${guestbook_params}' | oc process -f '${guestbook_template}' --param-file=-" '"root"'
os::cmd::expect_success_and_text "cat '${guestbook_params}' | oc process -f '${guestbook_template}' --param-file=-" '"adminpass"'
os::cmd::expect_success_and_text "cat '${guestbook_params}' | oc process -f '${guestbook_template}' --param-file=-" '"redispass"'
# Argument values from command line have precedence over those from file
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}' -p ADMIN_USERNAME=myuser"     'ignoring value from file'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}' -p ADMIN_USERNAME=myuser"     '"myuser"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}' -p ADMIN_PASSWORD=mypassword" '"mypassword"'
os::cmd::expect_success_and_text "oc process -f '${guestbook_template}' --param-file='${guestbook_params}' -p REDIS_PASSWORD=rrr"        '"rrr"'
# Set template parameters from parameter file with multiline values
os::cmd::expect_success_and_text "oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=${TEST_DATA}/templates/template_required_params.env -o yaml" 'first$'
os::cmd::expect_success 'oc delete template ruby-helloworld-sample'
# Parameter file failure cases
os::cmd::expect_failure_and_text "oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=does/not/exist"  'no such file or directory'
os::cmd::expect_failure_and_text "oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=${TEST_DATA}"   'is a directory'
os::cmd::expect_failure_and_text "oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=/dev/null"       'parameter required_param is required and must be specified'
os::cmd::expect_success "oc process -f '${guestbook_template}' --param-file=/dev/null --param-file='${guestbook_params}'"
os::cmd::expect_failure_and_text "echo 'fo%(o=bar' | oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=-"        'invalid parameter assignment'
os::cmd::expect_failure_and_text "echo 'S P A C E S=test' | oc process -f ${TEST_DATA}/templates/template_required_params.yaml --param-file=-" 'invalid parameter assignment'
# Handle absent parameter
os::cmd::expect_failure_and_text "oc process -f '${guestbook_template}' -p ABSENT_PARAMETER=absent" 'unknown parameter name'
os::cmd::expect_success "oc process -f '${guestbook_template}' -p ABSENT_PARAMETER=absent --ignore-unknown-parameters"
echo "template+parameters: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/templates/data-precision"
# Run as cluster-admin to allow choosing any supplemental groups we want
# Ensure large integers survive unstructured JSON creation
os::cmd::expect_success 'oc create -f ${TEST_DATA}/templates/template-type-precision.json'
# ... and processing
os::cmd::expect_success_and_text 'oc process template-type-precision' '1000030003'
os::cmd::expect_success_and_text 'oc process template-type-precision' '2147483647'
os::cmd::expect_success_and_text 'oc process template-type-precision' '9223372036854775807'
# ... and re-encoding as structured resources
os::cmd::expect_success 'oc process template-type-precision | oc create -f -'
# ... and persisting
os::cmd::expect_success_and_text 'oc get pod/template-type-precision -o json' '1000030003'
os::cmd::expect_success_and_text 'oc get pod/template-type-precision -o json' '2147483647'
os::cmd::expect_success_and_text 'oc get pod/template-type-precision -o json' '9223372036854775807'
# Ensure patch computation preserves data
patch='{"metadata":{"annotations":{"comment":"patch comment"}}}'
os::cmd::expect_success "oc patch pod template-type-precision -p '${patch}'"
os::cmd::expect_success_and_text 'oc get pod/template-type-precision -o json' '9223372036854775807'
os::cmd::expect_success_and_text 'oc get pod/template-type-precision -o json' 'patch comment'
os::cmd::expect_success 'oc delete template/template-type-precision'
os::cmd::expect_success 'oc delete pod/template-type-precision'
echo "template data precision: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_start "cmd/templates/process"
# This test validates oc process
# fail to process two templates by name
os::cmd::expect_failure_and_text 'oc process name1 name2' 'template name must be specified only once'
# fail to pass a filename or template by name
os::cmd::expect_failure_and_text 'oc process' 'Must pass a filename or name of stored template'
# can't ask for parameters and try process the template
os::cmd::expect_failure_and_text 'oc process template-name --parameters --param=someval' '\-\-parameters flag does not process the template, can.t be used with \-\-param'
os::cmd::expect_failure_and_text 'oc process template-name --parameters -p someval' '\-\-parameters flag does not process the template, can.t be used with \-\-param'
os::cmd::expect_failure_and_text 'oc process template-name --parameters --labels=someval' '\-\-parameters flag does not process the template, can.t be used with \-\-labels'
os::cmd::expect_failure_and_text 'oc process template-name --parameters -l someval' '\-\-parameters flag does not process the template, can.t be used with \-\-labels'
os::cmd::expect_failure_and_text 'oc process template-name --parameters --output=yaml' '\-\-parameters flag does not process the template, can.t be used with \-\-output'
os::cmd::expect_failure_and_text 'oc process template-name --parameters -o yaml' '\-\-parameters flag does not process the template, can.t be used with \-\-output'
os::cmd::expect_failure_and_text 'oc process template-name --parameters --raw' '\-\-parameters flag does not process the template, can.t be used with \-\-raw'
os::cmd::expect_failure_and_text 'oc process template-name --parameters --template=someval' '\-\-parameters flag does not process the template, can.t be used with \-\-template'
# providing a value more than once should fail
os::cmd::expect_failure_and_text 'oc process template-name key=value key=value' 'provided more than once: key'
os::cmd::expect_failure_and_text 'oc process template-name --param=key=value --param=key=value' 'provided more than once: key'
os::cmd::expect_failure_and_text 'oc process template-name key=value --param=key=value' 'provided more than once: key'
os::cmd::expect_failure_and_text 'oc process template-name key=value other=foo --param=key=value --param=other=baz' 'provided more than once: key, other'
required_params="${TEST_DATA}/templates/template_required_params.yaml"
# providing something other than a template is not OK
os::cmd::expect_failure_and_text "oc process -f '${TEST_DATA}/templates/basic-users-binding.json'" 'not a valid Template but'
# not providing required parameter should fail
os::cmd::expect_failure_and_text "oc process -f '${required_params}'" 'parameter required_param is required and must be specified'
# not providing an optional param is OK
os::cmd::expect_success "oc process -f '${required_params}' --param=required_param=someval"
os::cmd::expect_success "oc process -f '${required_params}' -p required_param=someval | oc create -f -"
# parameters with multiple equal signs are OK
os::cmd::expect_success "oc process -f '${required_params}' required_param=someval=moreval | oc create -f -"
os::cmd::expect_success "oc process -f '${required_params}' -p required_param=someval=moreval2 | oc create -f -"
os::cmd::expect_success "oc process -f '${required_params}' -p required_param=someval=moreval3 | oc create -f -"
# we should have overwritten the template param
os::cmd::expect_success_and_text 'oc get user someval -o jsonpath={.metadata.name}' 'someval'
os::cmd::expect_success_and_text 'oc get user someval=moreval -o jsonpath={.metadata.name}' 'someval=moreval'
os::cmd::expect_success_and_text 'oc get user someval=moreval2 -o jsonpath={.metadata.name}' 'someval=moreval2'
os::cmd::expect_success_and_text 'oc get user someval=moreval3 -o jsonpath={.metadata.name}' 'someval=moreval3'
# providing a value not in the template should fail
os::cmd::expect_failure_and_text "oc process -f '${required_params}' --param=required_param=someval --param=other_param=otherval" 'unknown parameter name "other_param"'
# failure on values fails the entire call
os::cmd::expect_failure_and_text "oc process -f '${required_params}' --param=required_param=someval --param=optional_param" 'invalid parameter assignment in'
# failure on labels fails the entire call
os::cmd::expect_failure_and_text "oc process -f '${required_params}' --param=required_param=someval --labels======" 'error parsing labels'
# values are not split on commas, required parameter is not recognized
os::cmd::expect_failure_and_text "oc process -f '${required_params}' --param=optional_param=a,required_param=b" 'parameter required_param is required and must be specified'
# warning is printed iff --value/--param looks like two k-v pairs separated by comma
os::cmd::expect_success_and_text "oc process -f '${required_params}' --param=required_param=a,b=c,d" 'no longer accepts comma-separated list'
os::cmd::expect_success_and_not_text "oc process -f '${required_params}' --param=required_param=a_b_c_d" 'no longer accepts comma-separated list'
os::cmd::expect_success_and_not_text "oc process -f '${required_params}' --param=required_param=a,b,c,d" 'no longer accepts comma-separated list'
# warning is not printed for template values passed as positional arguments
os::cmd::expect_success_and_not_text "oc process -f '${required_params}' required_param=a,b=c,d" 'no longer accepts comma-separated list'
# set template parameter to contents of file
os::cmd::expect_success_and_text "oc process -f '${required_params}' --param=required_param='`cat ${TEST_DATA}/templates/multiline.txt`'" 'also,with=commas'
echo "process: ok"
os::test::junit::declare_suite_end

os::test::junit::declare_suite_end

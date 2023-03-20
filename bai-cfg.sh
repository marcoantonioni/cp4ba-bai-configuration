#!/bin/bash

FORCE_DELETION=false

#-------------------------------
resourceExist () {
  if [ $(oc get $2 -n $1 $3 | grep $3 | wc -l) -lt 1 ];
  then
      return 0
  fi
  return 1
}

#-------------------------------
waitForResourceCreated () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
#    echo "time to wait: $4"

  while [ true ]
  do
      resourceExist $1 $2 $3 $4
      if [ $? -eq 0 ]; then
          echo "Wait for resource '$3' in namespace '$1' created, sleep $4 seconds"
          sleep $4
      else
          break
      fi
  done
}

waitForEventprocessorReady () {
  while [ true ]
  do
      _READY=$(oc get -n ${CP4BA_AUTO_NAMESPACE} eventprocessors.eventprocessing.automation.ibm.com iaf-insights-engine-event-processor | grep -v NAME | awk '{print $2}')
      if [ "${_READY}" = "True" ]; then
          break
      else
          echo "Wait for eventprocessor status READY..."
          sleep 5
      fi
  done
}

#-----------------------------------------------
# Setup and checks
#-----------------------------------------------

if [ "$1" == '' ]; 
then
  echo -e "\e[1;31m -- Param var for CP4BA_AUTO_NAMESPACE is not set -- \e[0m"
else
  export CP4BA_AUTO_NAMESPACE=$1
fi

if [ "${CP4BA_AUTO_NAMESPACE}" == '' ];
then
  echo -e "\e[1;31m -- Env var CP4BA_AUTO_NAMESPACE is not set -- \e[0m"
  exit 0
else
  echo -e "\e[1;42m -- Using env var CP4BA_AUTO_NAMESPACE=${CP4BA_AUTO_NAMESPACE} -- \e[0m"
fi

#-----------------------------------------------
# Vars
#-----------------------------------------------
export TRACE=no
export BPC_SECRET_NAME="custom-bpc-workforce-secret"

#-----------------------------------------------
# Create secret BPC Workforce
#-----------------------------------------------
echo "Create secret '${BPC_SECRET_NAME}' in namespace '${CP4BA_AUTO_NAMESPACE}'"

username=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} ibm-ban-secret -ojsonpath='{.data.appLoginUsername}'|base64 -d)
password=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} ibm-ban-secret -ojsonpath='{.data.appLoginPassword}'|base64 -d)
if [[ "$TRACE" == "yes" ]]; then
echo "===> ibm-ban-secret: " $username " / " $password
fi

iamhost="https://"$(oc get route -n ${CP4BA_AUTO_NAMESPACE} cp-console -o jsonpath="{.spec.host}")
cp4ahost="https://"$(oc get route -n ${CP4BA_AUTO_NAMESPACE} cpd -o jsonpath="{.spec.host}")
if [[ "$TRACE" == "yes" ]]; then
echo "===> iamhost: " ${iamhost}
echo "===> cp4ahost: " ${cp4ahost}
fi

iamaccesstoken=$(curl -sk -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" -d "grant_type=password&username=${username}&password=${password}&scope=openid" ${iamhost}/idprovider/v1/auth/identitytoken | jq -r .access_token)
if [[ "$TRACE" == "yes" ]]; then
echo "===> iamaccesstoken: " ${iamaccesstoken}
fi

zentoken=$(curl -sk "https://"$(oc get route -n ${CP4BA_AUTO_NAMESPACE} | grep ^cpd |awk '{print $2}')/v1/preauth/validateAuth -H "username:${username}" -H "iam-token: ${iamaccesstoken}" | jq -r .accessToken)
if [[ "$TRACE" == "yes" ]]; then
echo "===> zentoken: " ${zentoken}
fi

type=$(oc get icp4acluster -n ${CP4BA_AUTO_NAMESPACE} -o yaml | grep -E "sc_deployment_type|olm_deployment_type"| tail -1 |awk '{print $2}')
if [[ "$TRACE" == "yes" ]]; then
echo "===> deloyment type: " ${type}
fi

URL=$(oc get cm -n ${CP4BA_AUTO_NAMESPACE} $(oc get cm -n ${CP4BA_AUTO_NAMESPACE} | grep access-info | awk '{print $1}') -o yaml | grep "Business Automation Workflow .* base URL" | head -1 | awk '{print $7}' | sed s'/.$//')
bpmSystemID=$(curl -sk -X GET ${URL}/rest/bpm/wle/v1/systems -H "Accept: application/json" -H "Authorization: Bearer ${zentoken}" | jq -r .data.systems[].systemID)
adminUsername=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} $(oc get secret -n ${CP4BA_AUTO_NAMESPACE} |grep bas-admin-secret | awk '{print $1}') -o jsonpath='{.data.adminUser}'|base64 -d)
adminPassword=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} $(oc get secret -n ${CP4BA_AUTO_NAMESPACE} |grep bas-admin-secret | awk '{print $1}') -o jsonpath='{.data.adminPassword}'|base64 -d)
if [[ "$TRACE" == "yes" ]]; then
echo "===> URL: "${URL}
echo "===> bpmSystemID: " $bpmSystemID
echo "===> adminUsername: " $adminUsername
echo "===> adminPassword: " $adminPassword
fi

secret_name=$(oc get icp4acluster -n ${CP4BA_AUTO_NAMESPACE} $(oc get icp4acluster -n ${CP4BA_AUTO_NAMESPACE} --no-headers | awk '{print $1}') -o jsonpath='{.spec.bai_configuration.business_performance_center.workforce_insights_secret}')
if [[ ! -z ${secret_name} ]]; then
  oc delete secret -n ${CP4BA_AUTO_NAMESPACE} ${secret_name} 
else
if [[ "$TRACE" == "yes" ]]; then
  echo "INFO: workforce_insights_secret not found"
fi
fi

cat <<EOF | oc apply -n ${CP4BA_AUTO_NAMESPACE} -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${BPC_SECRET_NAME}
stringData:
  workforce-insights-configuration.yml: |-
    - bpmSystemId: $bpmSystemID
      url: $URL 
      username: $adminUsername
      password: $adminPassword
EOF



#-----------------------------------------------
# Patch ICP4ACluster CR
#-----------------------------------------------

cluster_ba=$(oc get ICP4ACluster -n ${CP4BA_AUTO_NAMESPACE} | grep -v NAME | awk '{print $1}')

echo -e "\e[1;42m Patching CR '${cluster_ba}' in namespace '${CP4BA_AUTO_NAMESPACE}' \e[0m"

oc patch ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"spec": {"bai_configuration": {"business_performance_center": {"workforce_insights_secret": "'${BPC_SECRET_NAME}'"} } } }'

oc patch ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"spec": {"bai_configuration": {"bpmn": { "end_aggregation_delay": 10000, "force_elasticsearch_timeseries": true, "install": true } } } }'

oc patch ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"spec": {"bai_configuration": {"flink": {"create_route": true} } } }'

oc patch ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"spec": {"workflow_authoring_configuration": {"business_event": { "enable": true, "enable_task_api": true, "enable_task_record": true, "subscription": [ { "app_name": "*", "component_name": "*", "component_type": "*", "element_name": "*", "element_type": "*", "nature": "*", "version": "*" } ] } } } }'

echo -e "\e[1;42m Patched resource ${cluster_ba} in namespace [${CP4BA_AUTO_NAMESPACE}], now wait for operators ... \e[0m"

oc get ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} -o jsonpath='{.spec.bai_configuration}' | jq .
oc get ICP4ACluster ${cluster_ba} -n ${CP4BA_AUTO_NAMESPACE} -o jsonpath='{.spec.workflow_authoring_configuration}' | jq .

#-----------------------------------------------
# Wait Operators
#-----------------------------------------------

echo -e "\e[1;42m Wait for operators state 'Succeeded'... \e[0m"

while :
do
  all_csv=$(oc get csv --all-namespaces | grep -v NAMESPACE | wc -l)
  succeded_csv=$(oc get csv --all-namespaces | grep -v NAMESPACE | grep Succeeded | wc -l)

  echo "Total CSV "${all_csv}", succeeded CSV "${succeded_csv}

  if [ ${all_csv}"" == ${succeded_csv}"" ]; then
    if [ ${all_csv}"" != "1" ]; then
      echo "===> all operators succeeded, all [${all_csv}] succeded [${succeded_csv}] !"
      break
    fi
  else
    echo "===> waiting operators, all [${all_csv}] succeded [${succeded_csv}] ..."
    sleep 5
  fi
done

#-----------------------------------------------
# Force resource deletion (optional)
#-----------------------------------------------
if [ "${FORCE_DELETION}" == "true" ]; then

#-----------------------------------------------
# Delete BAI PVC
#-----------------------------------------------

echo -e "\e[1;42m Deleting BAI PVC... \e[0m"

bai_pvc=$(oc get pvc -n ${CP4BA_AUTO_NAMESPACE} | grep bai-pvc | awk '{print $1}')

if [ ${bai_pvc}"" == "" ]; then
  echo "===> bai-pvc not found"
else
  oc delete pvc ${bai_pvc} -n ${CP4BA_AUTO_NAMESPACE} --force=true --timeout=10s
  oc patch pvc ${bai_pvc} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"metadata": {"finalizers": null}}'
  sleep 5
  while :
  do
    bai_pvc=$(oc get pvc -n ${CP4BA_AUTO_NAMESPACE} | grep bai-pvc | awk '{print $1}')
    if [ ${bai_pvc}"" == "" ]; then
      echo -e "\e[1;42m Deleted BAI PVC from namespace [${CP4BA_AUTO_NAMESPACE}]... \e[0m"
      break
    else
      oc patch pvc ${bai_pvc} -n ${CP4BA_AUTO_NAMESPACE} --type=merge -p '{"metadata": {"finalizers": null}}'
      echo "===> bai-pvc finalizers patched, wait for deletion..."
      sleep 2
    fi
  done
fi

#-----------------------------------------------
# Delete resources
#-----------------------------------------------

insight_engine=$(oc get insightsengine -n ${CP4BA_AUTO_NAMESPACE} | grep -v NAME | awk '{print $1}')
mls_wfi_deployment=$(oc get deployment -n ${CP4BA_AUTO_NAMESPACE} | grep mls-wfi | awk '{print $1}')

oc delete insightsengine -n ${CP4BA_AUTO_NAMESPACE} ${insight_engine}

oc delete eventprocessors -n ${CP4BA_AUTO_NAMESPACE} iaf-insights-engine-event-processor

oc delete deployment -n ${CP4BA_AUTO_NAMESPACE} ${mls_wfi_deployment}

echo -e "\e[1;42m Deleted WFI resources from namespace [${CP4BA_AUTO_NAMESPACE}], now wait for new CR eventprocessor... \e[0m"

# force operators reconciliation
oc get pods -n ${CP4BA_AUTO_NAMESPACE} | grep operator | awk '{print $1}' | xargs oc delete pod -n ${CP4BA_AUTO_NAMESPACE}

waitForResourceCreated ${CP4BA_AUTO_NAMESPACE} eventprocessors iaf-insights-engine-event-processor 5

# Force deletion
fi

waitForEventprocessorReady


#-----------------------------------------------
# Create Flink route
#-----------------------------------------------

echo -e "\e[1;42m Creating Flink route... \e[0m"
FLINK_ROUTE_NAME="flink-ui"
EVENT_PROCESSOR_NAME=$(oc get eventprocessor -n ${CP4BA_AUTO_NAMESPACE} | grep True | awk '{print $1}')
FLINK_SECRET_NAME=$(oc get eventprocessor -n ${CP4BA_AUTO_NAMESPACE} ${EVENT_PROCESSOR_NAME} -o jsonpath='{.status.endpoints[0].authentication.secret.secretName}')
FLINK_USERNAME=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} ${FLINK_SECRET_NAME} -o jsonpath='{.data.username}' | base64 -d)
FLINK_PASSWORD=$(oc get secret -n ${CP4BA_AUTO_NAMESPACE} ${FLINK_SECRET_NAME} -o jsonpath='{.data.password}' | base64 -d)

FLINK_SERVICE_NAME=$(oc get eventprocessor -n ${CP4BA_AUTO_NAMESPACE} ${EVENT_PROCESSOR_NAME} -o jsonpath='{.status.endpoints[0].uri}' | sed 's/https:\/\///' | sed 's/\..*//')
oc create route -n ${CP4BA_AUTO_NAMESPACE} passthrough ${FLINK_ROUTE_NAME} --service=${FLINK_SERVICE_NAME} --port=proxy-client

FLINK_URL=$(oc get route -n ${CP4BA_AUTO_NAMESPACE} ${FLINK_ROUTE_NAME} -o jsonpath='{.spec.host}')

echo "Flink url:  https://"${FLINK_URL}
echo "Flink username: "${FLINK_USERNAME}
echo "Flink password: "${FLINK_PASSWORD}

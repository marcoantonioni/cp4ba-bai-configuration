#!/bin/bash
#-----------------------------------------------
# Create secret 'custom-bpc-workforce-secret'
#-----------------------------------------------
export TRACE=no
export CP4BA_AUTO_NAMESPACE="cp4ba"

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
  name: custom-bpc-workforce-secret
stringData:
  workforce-insights-configuration.yml: |-
    - bpmSystemId: $bpmSystemID
      url: $URL 
      username: $adminUsername
      password: $adminPassword
EOF

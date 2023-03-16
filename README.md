# Cloud Pak for Business Automation - BAI Configuration

## Update env vars in shell script

Set your namespace in var CP4BA_AUTO_NAMESPACE

Set TRACE as you need

## Create 'custom-bpc-workforce-secret'
Run ./bai-cfg.sh

## Update ICP4ACluster CR 

Access your CR cluster and update the following sections

### bai_configuration

Add the following YAML snippet (keep aligned the value of 'workforce_insights_secret' with the secret created using shell script)
```
    bpmn:
      install: true
      force_elasticsearch_timeseries: true
      end_aggregation_delay: 10000
    business_performance_center:
      all_users_access: true
      workforce_insights_secret: custom-bpc-workforce-secret
    flink:
      create_route: true
```

### workflow_authoring_configuration (if authoring environment)
https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/22.0.2?topic=parameters-business-automation-workflow-authoring
### baw_configuration (if NOT authoring environment)
https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/22.0.2?topic=parameters-business-automation-workflow-runtime-workstream-services

```
    business_event:
      enable: true
      enable_task_api: true
      enable_task_record: true
      subscription:
      - app_name: '*'
        component_name: '*'
        component_type: '*'
        element_name: '*'
        element_type: '*'
        nature: '*'
        version: '*'
```

## Wait for pods restarts

Pods of BAW runtime

Pods of IAF INSIGHTS ENGINE

## Access ES storage
```
ES_USER=$(oc get cm -n ${CP4BA_AUTO_NAMESPACE} icp4adeploy-cp4ba-access-info -o jsonpath='{.data.bai-access-info}' | grep "Elasticsearch Username" | awk '{print $3}')
ES_PASSW=$(oc get cm -n ${CP4BA_AUTO_NAMESPACE} icp4adeploy-cp4ba-access-info -o jsonpath='{.data.bai-access-info}' | grep "Elasticsearch Password" | awk '{print $3}')
echo "ES CREDENTIALS: "${ES_USER} / ${ES_PASSW}

IAF_ES_URL="https://"$(oc get routes -n ${CP4BA_AUTO_NAMESPACE} iaf-system-es -o jsonpath='{.spec.host}')

# monitored sources
curl -sk -X GET -u ${ES_USER}:${ES_PASSW} ${IAF_ES_URL}/icp4ba-bai-store-monitoring-sources/_search?pretty=true | jq .hits.hits[]._source.monitoringSources[].name

# dashboards 
curl -sk -X GET -u ${ES_USER}:${ES_PASSW} ${IAF_ES_URL}/icp4ba-bai-store-dashboards/_search?pretty=true | jq .hits.hits[]._source.name

# alerts
curl -sk -X GET -u ${ES_USER}:${ES_PASSW} ${IAF_ES_URL}/icp4ba-bai-store-alerts/_search?pretty=true

# indices
curl -sk -X GET -u ${ES_USER}:${ES_PASSW} ${IAF_ES_URL}/_cat/indices

#----------------------------------------
# completed process

KEY=icp4ba-bai-process-summaries-completed
IDX_NAME=$(curl -sk -X GET -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' ${IAF_ES_URL}/_cat/indices | grep ${KEY} | head -1 | awk '{print $3}')

# completed process infos
curl -sk -X POST -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' "${IAF_ES_URL}/${IDX_NAME}/_search?scroll=1m&pretty=true&size=1000" -d '{"query": {"term": {"_index" : "${IDX_NAME}"}}}'

# activities of completed process
curl -sk -X POST -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' ${IAF_ES_URL}/${IDX_NAME}/_search | jq . | more

# query with offset
curl -sk -X POST -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' ${IAF_ES_URL}/${IDX_NAME}/_search?pretty -d'{"from": 1, "size": 1}'

# use scroll id
RESPONSE=$(curl -sk -X POST -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' "${IAF_ES_URL}/${IDX_NAME}/_search?scroll=1m&pretty=true&size=1000" -d'{"query": {"term": {"_index" : "${IDX_NAME}"}}}')
SCROLL_ID=$(echo $RESPONSE | jq ._scroll_id | sed 's/\"//g')
curl -sk -X POST -u ${ES_USER}:${ES_PASSW} -H 'Content-Type: application/json' ${IAF_ES_URL}/${IDX_NAME}/_search -d '{ "scroll: "1m", "_scroll_id" : "${SCROLL_ID}"}'


# other index KEY
icp4ba-bai-process-summaries-active
icp4ba-bai-process-timeseries
icp4ba-bai-process-summaries-active
icp4ba-bai-process-summaries-completed
icp4ba-bai-case-summaries-active

icp4ba-bai-case-summaries-active       
icp4ba-bai-case-summaries-completed    

icp4ba-bai-odm-timeseries-idx-ibm-bai              
icp4ba-bai-ads-decision-execution-common-data  
icp4ba-bai-bawadv-summaries-completed  
icp4ba-bai-bawadv-summaries-active     
icp4ba-bai-store-monitoring-sources                                  
icp4ba-bai-content-timeseries          
icp4ba-bai-baml-workforce-insights             

icp4ba-pfs@ibmpfssavedsearches                                       

icp4ba-bai-store-dashboards                                          
icp4ba-bai-store-alerts                                              
icp4ba-bai-store-permissions                                         
icp4ba-bai-store-alertdetectionstates                                
icp4ba-bai-store-goals                                               
```


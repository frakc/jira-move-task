#!/bin/bash
brew install jq
if [ -z "$jira_project_name" ]; then
    echo "Jira Project Name is required."
    usage
fi

if [ -z "$jira_url" ]; then
    echo "Jira Url is required."
    usage
fi

if [ -z "$jira_token" ]; then
    echo "Jira token is required."
    usage
fi

if [ -z "$from_status" ]; then
    echo "Status of tasks for deployment is required."
    usage
fi

length=${#jira_project_name}

cred="$jira_user:$jira_token"

token=`echo -n $cred | base64`
echo "token $token"
query=$(jq -n \
    --arg jql "project = $jira_project_name AND status = '$from_status'" \
    '{ jql: $jql, startAt: 0, maxResults: 200, fields: [ "id" ], fieldsByKeys: false }'
);

echo "Query to be executed in Jira: $query"

tasks_to_close=$(curl -s \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $token" \
    --request POST \
    --data "$query" \
    "$jira_url/rest/api/2/search" | jq -r '.issues[].key'
)

echo "Tasks to transition: $tasks_to_close"

for task in ${tasks_to_close}
do
            echo "Transitioning $task"
            if [[ -n "$custom_jira_field" && -n "$custom_jira_field" ]]; then
                echo "Setting version of $task to $custom_jira_field"
                    query=$(jq -n \
                        --arg version $custom_jira_field \
                        "{ fields: { $custom_jira_field: [ \$version ] } }"
                    );

                curl \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Basic $token" \
                    --request PUT \
                    --data "$query" \
                    "$jira_url/rest/api/2/issue/$task"
            fi

                transition_id=$(curl -s \
                    -H "Authorization: Basic $token" \
                    "$jira_url/rest/api/2/issue/$task/transitions" |
                    jq -r --arg t "$to_status"  '.transitions[] | select( .to.name == $t ) | .id'
                )
                echo "ids: $transition_id"
                if [ -n "$transition_id" ]; then
                    echo "Transitioning  $task to $to_status"
                    query=$(jq -n \
                        --arg ti $transition_id \
                        '{ transition: { id: $ti } }'
                    );
                    echo "query: $query"
                    curl \
                        -H "Content-Type: application/json" \
                        -H "Authorization: Basic $token" \
                        --request POST \
                        --data "$query" \
                        "$jira_url/rest/api/2/issue/$task/transitions"
                else
                    echo "No matching transitions from status '$from_status' to '$to_status' for $task"
                fi

done
curl -X POST -H 'Content-type: application/json' --data '{"text":"Allow me to reintroduce myself!"}' $slack_webhoock

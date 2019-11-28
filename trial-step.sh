#!/bin/bash

jira_project_name="BTTES"
jira_url="https://alterplay.atlassian.net"
jira_token="WVhMArz7RhEaWkSvHqMk1E4F"
from_status="Team Review"
to_status="Ready for QA"
slack_webhoock="https://hooks.slack.com/services/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"
custom_jira_value="6"
custom_jira_field="BUILD NUMBER"

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
if [ -z "$custom_jira_field" ]; then
    echo "custom_jira_field is empty"
    usage
fi
if [ -z "$custom_jira_value" ]; then
    echo "custom_jira_value is empty."
    usage
fi
length=${#jira_project_name}

cred="artem@alty.co:$jira_token"

token=`echo -n $cred | base64`
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
            if [[ -ne "$custom_jira_field" && -ne "$custom_jira_value" ]]; then
                echo "Setting $custom_jira_field of $task to $custom_jira_field"
                    query=$(jq -n \
                        --arg c_value "$custom_jira_value" \
                        --arg c_name "$custom_jira_field" \
                        '{ "fields": { ($c_name) : [ $c_value ] } }'
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
release_message="Next build resolves following issues  \n\`\`\`\n"
for task in ${tasks_to_close}
do
    release_message="$release_message$jira_url/browse/$task\n"
done
release_message="$release_message\n\`\`\` "
release_message="\"$release_message\""
slack_query=$(jq -n --argjson message "$release_message" '{text:$message}');

echo "query $slack_query"
echo $(curl -X POST -H "Content-type: application/json" --data "$slack_query" $slack_webhoock)
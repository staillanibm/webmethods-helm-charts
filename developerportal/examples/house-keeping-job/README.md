# House Keeping Job - Data Backup [Under Construction]

Following scheduled job backups data `Theme`, `User`, `Collaboration` and `Core` of Developer Portal.

To move the Shell script into a job, we must change ...

* Evaluate the post and port of Developer Portal.
* Evaluate the administrator password.
* We need a container image with `curl` and `jq`.
* The backup zip file should be saved on a persistent volume. A persistent volume should be mounted.

## Shell Script

```
#/bin/bash
 
host=localhost:8083
passwd=<Admin Password>
 
cd $(dirname $0)
 
id=$(curl -X POST "https://${host}/portal/rest/v1/data/backup" -k -s -u "Administrator:${passwd}" -H "Content-type: application/json" -d '{"modules": ["Theme","User","Collaboration","Core" ]}' | jq -r ".id")
echo "Backup [$id] is ongoing ..."
sleep 1
status=$(curl -X GET "https://${host}/portal/rest/v1/data/status/${id}" -k -s -u "Administrator:${passwd}" -H "Content-type: application/json" | jq -r ".status")
while [[ "${status}" == "PENDING" || "${status}" = "INPROGRESS" ]];
do
  echo "... Backup status is [${status}], I am waiting ..."
  sleep 5
  status=$(curl -X GET "https://${host}/portal/rest/v1/data/status/${id}" -k -s -u "Administrator:${passwd}" -H "Content-type: application/json" | jq -r ".status")
done;
if [[ "${status}" = "SUCCEEDED" ]];
then
  curl -X GET "https://${host}/portal/rest/v1/data/status/${id}/backup" -k -s -u "Administrator:${passwd}" -o ${id}.zip
  echo "... Backup [${id}] fetched."
else
  echo "... Cannot fetch backup because status is [${id}]."
fi;
 
# Count number of backups
count=$(find . -name "*.zip" | wc -l)
if [[ "${count}" -gt "10" ]];
then # only more then 10 files ...
  # Remove backups which are older than 10 days
  find . -name "*.zip" -mtime +10 | xargs rm
fi;
```
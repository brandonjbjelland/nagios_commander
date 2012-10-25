#!/bin/bash -
# Title:    nagios_commander.sh
# Author:   Brandon J. O'Connor <brandoconnor@gmail.com>
# Created:  08.19.12
# Purpose:  Provide a CLI interface to query and access common nagios functions remotely
# TODO:     query host health, service health, force rechecks
# TODO:     password input from a plain text file
# TODO:     service group or host group health
# TODO:     preserve username (if provided) in usage output
# TODO:     feedback given when downtime del isn't found or when it successfully dels

# Copyright 2012 Brandon J. O'Connor
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
##################

# globals can be defined here if desired
#NAG_HOST='nagios.sea.bigfishgames.com/nagios'
#USERNAME=''
#PASSWORD=''
NAG_HTTP_SCHEMA=http

unalias -a

function usage {
if [ -z $NAG_HOST ]; then $NAG_HOST='nagios.env/nagios'; fi
PROGNAME=$(basename $0)
DIR="$(cd "$( dirname "$0")" && pwd)"
echo "
        -n | --nag-host
            nagios HOSTNAME followed by its nagios directory
		-N | --nag-http-schema
			nagios URI schema
        -u | --username
            USER to execute commands
        -p | --password
            PASSWORD of the executing user
        -q | --query
            QUERY a nagios or device in nagios
                list (object or group object required)
                host_downtime
                service_downtime
                notifications (global)
                event_handlers (global)
                active_svc_checks (global)
                passive_svc_checks (global)
                active_host_checks (global)
                passive_host_checks (global)
        -c | --command
            COMMAND to issue in the form --command [action] [scope] [value]
                action: set
                        del
                        ack
                scope: (required for all but ack)
                        downtime
                        notifications
                        event_handlers
                        active_svc_checks
                        passive_svc_checks
                        active_host_checks
                        passive_host_checks
                 value:  (only required for global commands)
                        enable
                        disable
        -d | --down_id
            Downtime id number for deleting a specific downtime
        -Q | --quiet
            Flag for QUICK execution and QUIET output
        -h | --host
            HOST to execute the METHOD against. Leave blank to query all hosts.
        -H | --hostgroup
            HOSTGROUP to execute the METHOD against. -H followed by nothing for listing all.
        -s | --service_name
            SERVICE as execution object.
        -S | --servicegroup
            SERVICEGROUP an execution object. Follow with nothing to list all.
        -t | --time
             TIME in minutes to place on a downtime window, beginning now
        -C
            COMMENT (required by set downtime, ack)
        -*
            print this help dialog

Usage: $PROGNAME -n <nagios_instance> -c <commands> <method> -h <host> -H <host_group> -s <service> -S <service_group> -t <time_in_mins> -c <downtime_comment>
Examples:
$DIR/$PROGNAME -n $NAG_HOST -c set downtime -h cfengine01.sea -s PROC_CFAGENT_QUIET -t 1 -C 'downtime comment' -Q -u <USERNAME> -p <PASSWORD>
$DIR/$PROGNAME -n $NAG_HOST -q list -h -u <USERNAME> -p <PASSWORD>
$DIR/$PROGNAME -n $NAG_HOST -q host_downtime -u <USERNAME> -p <PASSWORD>
"
exit 1
}

while [ "$1" != "" ]; do
    case $1 in
            -n | --nag ) shift; NAG_HOST=$1;;
			-N | --nag_http_schema ) shift; NAG_HTTP_SCHEMA=$1;;
            -h | --host ) if [[ $2 = [A-Za-z]* ]]; then shift; HOST=$1 ; else HOST=list; fi ;;
            -H | --host_group ) if [[ $2 = [A-Za-z]* ]]; then shift; HOSTGROUP=$1; else HOSTGROUP=list; fi;;
            -s | --service ) if [[ $2 = [A-Za-z]* ]]; then shift; SERVICE=$1; else SERVICE=list; fi;;
            -S | --service_group ) if [[ $2 = [A-Za-z]* ]]; then shift; SERVICEGROUP=$1; else SERVICEGROUP=list; fi;;
            -t | --time ) shift; MINUTES=$1;;
            -q | --query ) shift; QUERY=$1;;
            -c | --command ) shift; ACTION=$1; if [[ ! $ACTION =~ ack ]];then shift; SCOPE=$1; if [[ $2 = [a-z]* ]]; then shift; VALUE=$1; fi; fi;;
            -C | --comment ) shift; COMMENT=$1;;
            -u | --username ) shift; USERNAME=$1;;
            -p | --password ) shift; PASSWORD=$1;;
            -d | --down_id ) shift; DOWN_ID=$1;;
            -Q | --quiet ) QUIET=1;;
            -D | --debug ) DEBUG=1;;
            *  | --help ) usage;;
        esac
        shift
done
if [ -n "$DEBUG" ]; then
    echo "DEBUG INFO: NAG_HOST=$NAG_HOST, SCOPE=$SCOPE, ACTION=$ACTION, VALUE=$VALUE, HOST=$HOST, HOSTGROUP=$HOSTGROUP, SERVICE=$SERVICE, SERVICEGROUP=$SERVICEGROUP, TIME=$MINUTES, QUERY=$QUERY, COMMENT=$COMMENT, TIME=$TIME, QUIET=$QUIET"
fi

if [ -z $USERNAME ]; then read -p "Username: " USERNAME; fi
if [ -z $PASSWORD ]; then read -s -p "Password for $USERNAME: " PASSWORD; echo ""; fi

if  [ $NAG_HOST ] && [ $USERNAME ] && [ $PASSWORD ] ; then
    if  [ ! $ACTION  ] && [ ! $QUERY ]; then
            echo "A query or command must be specified."; sleep 1; usage
    elif [ $ACTION ] && [ $QUERY ]; then
            echo "Cannot execute both a query and command."; sleep 1; usage
    fi
else
    echo "Script initiated with insufficient inputs. Exiting."; sleep 1; usage
fi

# verify creds are good on the fastest page possible
NAGIOS_INSTANCE="$NAG_HTTP_SCHEMA://$NAG_HOST/cgi-bin"
if [ -n "`curl -Ss $NAGIOS_INSTANCE/ -u $USERNAME:$PASSWORD | grep 'Authorization'`" ]; then
    echo "Bad credentials. Exiting"; exit 1
fi

function MAIN {
if  [ $QUERY ]; then
    if [[ $QUERY = list ]]; then
        if [[ $HOST = list  ]]; then
            DATA="--data hostgroup=all --data style=hostdetail"
            LIST_HOSTS
        elif [ $HOST ]; then
            DATA="--data host=$HOST --data style=detail"
            LIST_SERVICES
        elif [[ $HOSTGROUP = list ]]; then
            DATA="--data hostgroup=all --data style=summary"
            TYPE='host'
            LIST_GROUPS
        elif [ $HOSTGROUP ]; then
            DATA="--data hostgroup=$HOSTGROUP --data style=hostdetail"
            LIST_HOSTS
        elif [[ $SERVICEGROUP = list ]]; then
            DATA="--data servicegroup=all --data style=summary"
            TYPE='service'
            LIST_GROUPS
        elif [ $SERVICEGROUP ]; then
            DATA="--data servicegroup=$SERVICEGROUP --data style=detail"
            LIST_SERVICES
        fi
    else
        if [[ $QUERY = event_handlers ]]; then
            SEARCH='Event Handlers Enabled'
        elif [[ $QUERY = notifications ]]; then
            SEARCH='Notifications Enabled'
        elif [[ $QUERY = active_svc_checks ]]; then
            SEARCH='Service Checks Being Executed'
        elif [[ $QUERY = passive_svc_checks ]]; then
            SEARCH='Passive Service Checks'
        elif [[ $QUERY = active_host_checks ]]; then
            SEARCH='Host Checks Being Executed'
        elif [[ $QUERY = passive_host_checks ]]; then
            SEARCH='Passive Host Checks'
        elif [[ $QUERY = host_downtime ]]; then
            SCOPE='hosts'; DOWNTIME_QUERY; exit
        elif [[ $QUERY = service_downtime ]]; then
            SCOPE='services'; DOWNTIME_QUERY; exit
        else
            echo "A global object is required."; usage
        fi
        GLOBAL_QUERY
    fi

elif [ $ACTION ]; then
    if [ ! $HOST ] && [ ! $HOSTGROUP ] && [ ! $SERVICEGROUP ] && [[ $ACTION = set ]]; then
        if [[ $SCOPE = notifications ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='12'; VALUE='enabled'; GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then CMD_TYP='11'; VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Notifications Enabled'; GLOBAL_QUERY
            fi
        elif [[ $SCOPE = event_handlers ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='41'; VALUE='enabled';GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then CMD_TYP='42';VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Event Handlers Enbled'; GLOBAL_QUERY
            fi
        elif [[ $SCOPE = active_service_checks ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='35'; VALUE='enabled'; GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then CMD_TYP='36'; VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Service Checks Being Executed'; GLOBAL_QUERY
            fi
        elif [[ $SCOPE = passive_service_checks ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='37';  VALUE='enabled'; GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then CMD_TYP='38'; VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Passive Service Checks'; GLOBAL_QUERY
            fi
        elif [[ $SCOPE = active_host_checks ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='88'; VALUE='enabled';  GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then  CMD_TYP='89'; VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Host Checks Being Executed'; GLOBAL_QUERY
            fi
        elif [[ $SCOPE = passive_host_checks ]]; then
            if [[ $VALUE =~ en ]]; then CMD_TYP='90';  VALUE='enabled'; GLOBAL_COMMAND;
            elif [[ $VALUE =~ dis ]]; then CMD_TYP='91'; VALUE='disabled'; GLOBAL_COMMAND;
            else
                echo "An action is required (enable or disable)"
                SEARCH='Passive Host Checks'; GLOBAL_QUERY
            fi
        fi
    elif [[ $ACTION = set ]] || [[ $ACTION = ack ]] ; then
        if [[ $SCOPE = downtime ]]; then
            if [ $HOST ] && [ ! $SERVICE ]; then
                CMD_TYP='55'; DATA="--data host=$HOST --data trigger=0"
            elif [ $HOST ] && [ $SERVICE ]; then
                CMD_TYP='56'
                DATA="--data service=$SERVICE --data host=$HOST --data trigger=0"
            elif [ $HOSTGROUP ]; then
                CMD_TYP='84'; DATA="--data hostgroup=$HOSTGROUP"
            elif [ $SERVICEGROUP ]; then
                CMD_TYP='122'; DATA="--data servicegroup=$SERVICEGROUP"
            else
                echo "$SCOPE needs to be applied to a service, host, hostgroup or servicegroup. Exiting."
                exit 1
            fi
            SET_DOWNTIME
        elif [[ $ACTION = ack ]] && [ $HOST ] && [ $SERVICE ] ; then
            DATA="--data cmd_typ=34 --data service=$SERVICE"; ACKNOWLEDGE
        elif [[ $ACTION = ack ]] && [ $HOST ]; then
            DATA="--data cmd_typ=33"; ACKNOWLEDGE
        fi
    elif [[ $ACTION = del ]]; then
        if [ $DOWN_ID ]; then
            CMD_TYP=79 ; DELETE_DOWNTIME; CMD_TYP=78 ; DELETE_DOWNTIME
            exit 0
        elif [ $SERVICE ] && [ $HOST ]; then
            COUNT=1; SCOPE=services
            while [ ! $DOWN_ID ] && [ $COUNT -lt 5 ] ; do
                FIND_DOWN_ID; COUNT=$[$COUNT+1]
            done
            if [ ! $DOWN_ID ]; then echo "Could not find downtime for $HOST. Exiting."
                exit 1
            fi
            DELETE_DOWNTIME; exit 0
        elif [ $HOST ]; then
			CMD_TYP=78
            COUNT=1; SCOPE=hosts
            while [ ! $DOWN_ID ] && [ $COUNT -lt 5 ] ; do
                FIND_DOWN_ID; COUNT=$[$COUNT+1]
            done
            if [ ! $DOWN_ID ]; then echo "Could not find downtime for $HOST. Exiting."
                exit 1
            fi
            DELETE_DOWNTIME; exit
        else
            echo "No host, service or downtime-id specified. Listing current downtimes now."
            SCOPE=hosts; DOWNTIME_QUERY; SCOPE=services; DOWNTIME_QUERY
        fi
    else
        echo "Command not recognized."; usage
    fi
else
    echo "Method not specified."; usage
fi

}

function SET_DOWNTIME {
NOW_ADD_MINS=$(date +"%Y-%m-%dT%H:%M:%S" -d "+$MINUTES minute")
if [ ! $MINUTES ]; then
    echo "Time value not set. Cannot submit downtime requests without a duration."
    exit
fi
NOW=$(date +"%Y-%m-%dT%H:%M:%S")
curl -sS $DATA $NAGIOS_INSTANCE/cmd.cgi -u "$USERNAME:$PASSWORD" \
    --data cmd_typ=$CMD_TYP \
    --data cmd_mod=2 \
    --data "com_data=$COMMENT" \
    --data "start_time=$NOW" \
    --data "end_time=$NOW_ADD_MINS" \
    --data fixed=1 \
    --data hours=2 \
    --data minutes=0 \
    --data btnSubmit=Commit \
    --output /dev/null
if [ $? -eq 1 ]; then echo "curl failed. Command not sent."; exit 1; fi
if [ -z $QUIET ]; then
    if [ $SERVICE ]; then SCOPE=services; elif [ $HOST ]; then SCOPE=hosts; fi
    if [ $HOST ] || [ $SERVICE ]; then
        COUNT=2; FIND_DOWN_ID; OLD_DID=$DOWN_ID;
        if [ $OLD_DID ]; then sleep 1; else OLD_DID=1 && DOWN_ID=1; fi
        while [ $DOWN_ID -eq $OLD_DID  ] && [ $COUNT -le 15 ] ; do
            sleep 1; FIND_DOWN_ID; COUNT=$[$COUNT+1]
        done
        if [ $DOWN_ID -eq 1 ]; then
            echo "Could not find newly created downtime. Exiting."; exit 1
        fi
    fi
    echo $DOWN_ID
fi
exit
}

function FIND_DOWN_ID {
if [[ $SCOPE = hosts ]]; then
    # XXX what is this?
    # if [ ! $COUNT ]; then  echo -e "hostname\tdowntime-id"; fi
    DOWN_ID=$(curl -Ss $NAGIOS_INSTANCE/extinfo.cgi -u $USERNAME:$PASSWORD \
    --data type=6 | grep "extinfo.cgi" | sed -e'/service=/d' |\
    awk -F"<td CLASS='downtime" '{print $2" "$4" "$7" "$10" "$5}' |\
    awk -F'>' '{print $3"|||"$10}' | sed -e's/<\/td//g' -e's/<\/A//g' |\
    egrep "$HOST" | egrep -o "[0-9]+" | sort -rn | head -n1)
    if [ ! $DOWN_ID ]; then DOWN_ID=1; fi
elif [[ $SCOPE = services ]]; then
    # XXX what is this?
    #if [ ! $COUNT ]; then echo -e "hostname\t\tservice\t\tdowntime-id"; fi
    DOWN_ID=$(curl -Ss $NAGIOS_INSTANCE/extinfo.cgi -u $USERNAME:$PASSWORD \
    --data type=6 | grep "extinfo.cgi" | grep "service=" |\
    awk -F"<td CLASS='downtime" '{print $2" "$3" "$5" "$7" "$8" "$6" "$11}' |\
    awk -F'>' '{print $3"|||"$7"|||"$18}' | sed -e's/<\/td//g' -e's/<\/A//g' |\
    column -c8 -t -s"|||" | egrep "$HOST" | grep "$SERVICE" | egrep -o "[0-9]+" |\
    sort -rn | head -n1)
if [ ! $DOWN_ID ]; then DOWN_ID=1; fi
if [ $? -eq 1 ]; then echo "curl failed"; exit 1; fi
fi
}

function DOWNTIME_QUERY {
if [[ $SCOPE = hosts ]]; then
    curl -Ss $NAGIOS_INSTANCE/extinfo.cgi --data type=6 -u $USERNAME:$PASSWORD |\
    grep "extinfo.cgi" | sed -e'/service=/d' |\
    awk -F"<td CLASS='downtime" '{print $2" "$4" "$7" "$10" "$5}' |\
    awk -F'>' '{print $3"|||"$10"|||"$8"|||"$6"|||"$12}' |\
    sed -e's/<\/td//g' -e's/<\/A//g' |\
    sed "1 i \Hostname|||Downtime-id|||End_date_and_time|||Author|||Comment" |\
    column -c7 -t -s"|||"
elif [[ $SCOPE = services ]]; then
    curl -Ss $NAGIOS_INSTANCE/extinfo.cgi --data type=6 -u $USERNAME:$PASSWORD |\
    grep "extinfo.cgi" | grep "service=" |\
    awk -F"<td CLASS='downtime" '{print $2" "$3" "$5" "$7" "$8" "$6" "$11}' |\
    awk -F'>' '{print $3"|||"$7"|||"$18"|||"$14"|||"$10"|||"$16}' |\
    sed -e's/<\/td//g' -e's/<\/A//g' |\
    sed "1 i \Hostname|||Service|||Downtime-id|||End_date_and_time|||Author|||Comment" |\
    column -c8 -t -s"|||"
fi
if [ $? -eq 1 ]; then echo "curl failed"; exit 1; fi
}

function DELETE_DOWNTIME {
curl -Ss --output /dev/null $NAGIOS_INSTANCE/cmd.cgi \
    --data cmd_mod=2 \
    --data cmd_typ=$CMD_TYP \
    --data down_id=$DOWN_ID \
    --data btnSubmit=Commit \
    -u $USERNAME:$PASSWORD
if [ $? -eq 1 ]; then echo "curl failed"; exit 1; fi
}

function GLOBAL_COMMAND {
curl -sS $DATA \
    "$NAGIOS_INSTANCE/cmd.cgi" \
    --data cmd_mod=2 \
    --data cmd_typ=$CMD_TYP \
    --data btnSubmit=Commit \
    -u $USERNAME:$PASSWORD |\
    grep -o 'Your command request was successfully submitted to Nagios for processing.'
if [ $? -eq 1 ]; then echo "curl failed. Command not sent."; exit 1; fi
QUERY=$SCOPE; RESULT=`MAIN`
until [[ $SCOPE:$VALUE = $RESULT ]]; do sleep 1; RESULT=`MAIN`; done
echo $RESULT
exit
}

function GLOBAL_QUERY {
HTML=`curl  -sS $NAGIOS_INSTANCE/extinfo.cgi \
    --data type=0 \
    -u $USERNAME:$PASSWORD | grep "$SEARCH"`
if [ $? -eq 1 ]; then echo "curl failed"; exit 1; fi
MATCH=`echo $HTML | grep -i 'yes'`
if [ -n "$MATCH" ]; then echo "$QUERY:enabled"; exit
else echo  "$QUERY:disabled"; exit; fi
}

function ACKNOWLEDGE {
curl -sS  $DATA \
    $NAGIOS_INSTANCE/cmd.cgi \
    --data host=$HOST \
    --data "com_data=$COMMENT" \
    --data cmd_mod=2 \
    --data btnSubmit=Commit \
    -u $USERNAME:$PASSWORD |\
    grep -o 'Your command request was successfully submitted to Nagios for processing.'
if [ $? -eq 1 ]; then echo "curl failed. Command not sent."; exit 1; fi
exit
}

function LIST_HOSTS {
echo -e "Hostname\tStatus"
curl -Ss $DATA $NAGIOS_INSTANCE/status.cgi -u $USERNAME:$PASSWORD |\
    grep 'extinfo.cgi?type=1&host=' | grep "statusHOST" | awk -F'</A>' '{print $1}' |\
    awk -F'statusHOST' '{print $2}'  |  awk -F"'>" '{print $3"\t"$1}' | column -c2 -t
exit
}

function LIST_GROUPS {
echo "List of all $TYPE\groups"
echo "---"
curl -Ss $DATA $NAGIOS_INSTANCE/status.cgi -u $USERNAME:$PASSWORD |\
    egrep "status(Even|Odd)" | grep "status.cgi?$TYPE\group=" | awk -F'</A>' '{print $1}' |\
    awk -F"${TYPE}group=" '{print $2}' | awk -F'&' '{print $1}' | column -c2 -t
exit
}

function LIST_SERVICES {
echo List of all services on $HOST$SERVICEGROUP
echo ---
curl -Ss $DATA $NAGIOS_INSTANCE/status.cgi -u $USERNAME:$PASSWORD |\
    grep 'extinfo.cgi?type=2&host=localhost&service=' | grep ALIGN=LEFT |\
    awk -F'status' '{print $2}' | awk -F"host=localhost&service=" '{print $2}' |\
    awk -F"'>" '{print $1}'
exit
}

MAIN

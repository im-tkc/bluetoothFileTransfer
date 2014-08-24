#!/bin/bash

BLUETOOTH_SERVICE='bluetooth.service'

GREEN_TEXT_COLOR="\e[0;32m"
RED_TEXT_COLOR="\e[0;31m"
NORMAL_TEXT_COLOR="\e[0;00m"

deviceMACAddress=
transferList=()

function main() {
    checkForExecutable hcitool 
    checkForExecutable obexftp # you may have to install openobex-apps and obexftp if it is not installed
    checkForExecutable sdptool

    while true; do
        clear
        echo 'Bluetooth Manager'
        echo '1) Query for bluetooth service'
        echo '2) Send file(s) to another device'
        echo '3) Quit'

        read -p "Please select your choice: " input
        case $input in 
            1) queryBluetoothService; break;;
            2) sendFiles; break;;
            3) exit; break;;
            *) echo 'Invalid input. Please try again.'; sleep 1;
        esac
    done
}

function checkForExecutable() {
    executable=$1
    which $executable 2>&1> /dev/null
    result=`echo $?`
    if [ $result -eq 1 ]; then
        echo "Oops! $executable is not installed. Please install them via yum."
        exit 1
    fi
}

function queryBluetoothService() {
    isActive=`checkBluetoothService 'Active:' 'active'`
    isLoaded=`checkBluetoothService 'Loaded:' 'enabled'`

    [[ $isLoaded == 0 ]] && loadedStatus="${GREEN_TEXT_COLOR}enabled${NORMAL_TEXT_COLOR}" || loadedStatus="${RED_TEXT_COLOR}disabled${NORMAL_TEXT_COLOR}"
    [[ $isActive == 0 ]] && activeStatus="${GREEN_TEXT_COLOR}running${NORMAL_TEXT_COLOR}" || activeStatus="${RED_TEXT_COLOR}stopped${NORMAL_TEXT_COLOR}"

    echo -e "$BLUETOOTH_SERVICE has been $loadedStatus"
    echo -e "$BLUETOOTH_SERVICE is $activeStatus"
}

function sendFiles() {
    isBluetoothRunning
    queryDevice # NOTE: This will update the variable $deviceMACAddress
    obexChannel=`getOBEXChannel $deviceMACAddress`
    getTransferList # NOTE: This will update the variable $transferList

    for index in ${!transferList[@]}; do
        path=${transferList[$index]}

        if [[ -d $path ]]; then
            FILE_LIST="fileList.txt"
            find $path -maxdepth 1 -type f > $FILE_LIST

            while read file; do
                sendFile $deviceMACAddress $obexChannel "$file"
            done < $FILE_LIST

            rm $FILE_LIST
        elif [[ -f $path ]]; then
            sendFile $deviceMACAddress $obexChannel "$path"
        fi
    done
}

function isBluetoothRunning() {
    isActive=`checkBluetoothService 'Active:' 'active'`

    if [[ $isActive != 0 ]]; then
        PS3='It seems that bluetooth service is not running do you want to start the service? '
        select prompt in y n; do
            if [[ $prompt == "y" ]]; then
                sudo systemctl start "$BLUETOOTH_SERVICE"
                sleep 3
                break
            elif [[ $prompt == "n" ]]; then
                echo "Bluetooth file transfer aborted"
                exit 2
            fi
        done
    fi
}

function checkBluetoothService() {
    serviceKeyword=$1
    serviceStatus=$2

    bluetoothServiceStatus=`systemctl status $BLUETOOTH_SERVICE`
    isActive=`search "$bluetoothServiceStatus" "$serviceKeyword" "$serviceStatus"`

    echo $isActive
}

function search() {
    TEXT_TO_SEARCH=$1
    searchTerms=${@:2}
    result=$TEXT_TO_SEARCH

    for term in ${searchTerms}; do
        result=`echo "$result" | grep -w "$term"`
        isFound=`echo $?`
    done
 
    echo $isFound
}

function queryDevice() {
    DEVICES_LIST='listOfDevices.txt'
    TEMP_LIST='tempDeviceList.txt'

    echo "Scanning for device(s)..."
    hcitool scan > $DEVICES_LIST
    tail -n +2 $DEVICES_LIST | cat -n > $TEMP_LIST
    mv $TEMP_LIST $DEVICES_LIST
    numberOfDevices=`cat $DEVICES_LIST | wc -l`

    if [ -s $DEVICES_LIST ]; then
        while true; do
            echo
            echo '==============='
            echo '= Device List ='
            echo '==============='
            cat $DEVICES_LIST

            read -p "Enter the corresponding number that you wish to send/receive data to/from that device: " input
            if [[ ! ($input -gt 0 && $input -le numberOfDevices) || -z $input ]]; then
                echo 'Invalid input. Please try again.'
                sleep 1
            else
                deviceMACAddress=`grep -w "^\W*$input" $DEVICES_LIST | awk '{print $2}'`
                break
            fi
        done
        rm $DEVICES_LIST
    else
        rm $DEVICES_LIST
        echo "No device found. Please ensure that bluetooth service is running and it is set to be visible."
        exit 1
    fi
}

function getOBEXChannel() {
    deviceMACAddress=$1
    DEVICE_SERVICE_LIST='listOfDeviceServices.txt'
    
    sdptool browse $deviceMACAddress | awk '{FS="\n"; RS="\n\n"} /OBEX Object Push/ {print}' > $DEVICE_SERVICE_LIST
    channel=`grep "^\W*Channel" $DEVICE_SERVICE_LIST | awk '{FS=":"} {print $2}'`

    rm $DEVICE_SERVICE_LIST
    echo $channel
}

function getTransferList() {
    transferList=()
    counter=0

    while true; do
        echo
        read -p 'Specify the file to send: ' path
        if [[ ! -f $path && ! -d $path ]]; then
            echo 'It seems that you have entered an invalid file path. Please try again.'
        elif [[ -f $path  || -d $path ]]; then
            transferList[$counter]=$path
            counter=$[ $counter + 1 ]
        fi

        if [[ -d $path ]]; then
            echo 'WARNING: Only files of on this directory will be transferred. Files in subdirectory will be excluded.'
        fi

        PS3='Do you wish to add more files to be transferred? '
        select continue in y n; do
            if [[ $continue == "n" ]]; then
                break 2
            else
                break
            fi
        done
    done
}

function sendFile() {
    deviceMACAddress=$1
    obexChannel=$2
    file=$3

    echo
    echo "Sending $file"
    obexftp --nopath --noconn --uuid none --bluetooth -b  $deviceMACAddress -B $obexChannel -put "$file"
    sleep 2 #for cooldown of the bluetooth server before sending a new file
}

main

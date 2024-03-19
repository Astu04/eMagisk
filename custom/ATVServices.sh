#!/system/bin/sh

# Base stuff we need
POGOPKG=com.nianticlabs.pokemongo
CONFIGFILE='/data/local/tmp/emagisk.config'
setprop net.dns1 1.1.1.1 && setprop net.dns2 8.8.8.8
get_config

# Check for the mitm pkg

get_mitm_pkg() { # This function is so hardcoded that I'm allergic to it 
	busybox ps aux | grep -E -C0 "pokemod|gocheats|sy1vi3" | grep -C0 -v grep | awk -F ' ' '/com.pokemod/{print $NF} /com.sy1vi3/{print $NF} /com.gocheats.launcher/{print $NF}' | grep -E -C0 "gocheats|pokemod|sy1vi3" | sed -e 's/^[0-9]*://' -e 's@:.*@@g' | sort | uniq
}

check_mitmpkg() {
	if [ "$(pm list packages com.pokemod.aegis.beta)" = "package:com.pokemod.aegis.beta" ]; then
		log -p i -t eMagiskATVService "Found Aegis developer version!"
		MITMPKG=com.pokemod.aegis.beta
	elif [ "$(pm list packages com.pokemod.aegis)" = "package:com.pokemod.aegis" ]; then
		log -p i -t eMagiskATVService "Found Aegis production version!"
		MITMPKG=com.pokemod.aegis
	elif [ "$(pm list packages com.pokemod.atlas.beta)" = "package:com.pokemod.atlas.beta" ]; then
		log -p i -t eMagiskATVService "Found Atlas developer version!"
		MITMPKG=com.pokemod.atlas.beta
	elif [ "$(pm list packages com.pokemod.atlas)" = "package:com.pokemod.atlas" ]; then
		log -p i -t eMagiskATVService "Found Atlas production version!"
		MITMPKG=com.pokemod.atlas
	elif [ "$(pm list packages com.sy1vi3.cosmog)" = "package:com.sy1vi3.cosmog" ]; then
		log -p i -t eMagiskATVService "Found Cosmog!"
		MITMPKG=com.sy1vi3.cosmog
	elif [ "$(pm list packages com.gocheats.launcher)" = "package:com.gocheats.launcher" ]; then
		log -p i -t eMagiskATVService "Found GC!"
		MITMPKG=com.gocheats.launcher
	else
		log -p i -t eMagiskATVService "No MITM installed. Abort!"
		exit 1
	fi
}

get_deviceName() {
	if [[ $MITMPKG == com.pokemod.atlas* ]] && [ -f /data/local/tmp/atlas_config.json ]; then
		mitmDeviceName=$(jq -r '.deviceName' /data/local/tmp/atlas_config.json)
	elif [[ $MITMPKG == com.pokemod.aegis* ]] && [ -f /data/local/tmp/aegis_config.json ]; then
		mitmDeviceName=$(jq -r '.deviceName' /data/local/tmp/aegis_config.json)
	elif [[ $MITMPKG == com.sy1vi3.cosmog ]] && [ -f /data/local/tmp/cosmog.json ]; then
		mitmDeviceName=$(jq -r '.device_id' /data/local/tmp/cosmog.json)
	elif [[ $MITMPKG == com.gocheats.launcher ]] && [ -f /data/local/tmp/config.json ]; then
		mitmDeviceName=$(jq -r '.device_name' /data/local/tmp/config.json)
	else
		log -p i -t eMagiskATVService "Couldn't find the config file"
	fi
}

# This is for the X96 Mini and X96W Atvs. Can be adapted to other ATVs that have a led status indicator

led_red(){
	if [ -e /sys/class/leds/led-sys ]; then
		echo 0 > /sys/class/leds/led-sys/brightness
	elif [ -e /sys/class/leds/sys_led ]; then
		echo 0 > /sys/class/leds/sys_led/brightness
	fi
}

led_blue(){
	if [ -e /sys/class/leds/led-sys ]; then
		echo 1 > /sys/class/leds/led-sys/brightness
	elif [ -e /sys/class/leds/sys_led ]; then
		echo 1 > /sys/class/leds/sys_led/brightness
	fi
}

# Stops MITM and Pogo and restarts MITM MappingService

force_restart() {
	pogo_process_running=$(busybox ps | grep com.nianticlabs.pokemongo)
	if [ -n "$pogo_process_running" ]; then
		killall com.nianticlabs.pokemongo
	fi
	if [ "$(pm list packages com.gocheats.launcher)" = "package:com.gocheats.launcher" ]; then
		am force-stop $MITMPKG
		sleep 5
		am start -n $MITMPKG/.MainActivity
	elif [[ $MITMPKG == com.pokemod* ]]; then
		if [[ $MITMPKG == com.pokemod.atlas* ]]; then
			am stopservice $MITMPKG/com.pokemod.atlas.services.MappingService
		elif [[ $MITMPKG == com.pokemod.aegis* ]]; then
			am stopservice $MITMPKG/com.pokemod.aegis.services.MappingService
		fi
		am force-stop $MITMPKG
		sleep 5
		android_version=$(getprop ro.build.version.release)
		if [ "$(echo $android_version | cut -d. -f1)" -ge 8 ]; then
			monkey -p $MITMPKG 1 # To solve "Error: app is in background uid null"
			sleep 3
   			input keyevent KEYCODE_HOME
		fi
		if [[ $MITMPKG == com.pokemod.atlas* ]]; then
			am startservice $MITMPKG/com.pokemod.atlas.services.MappingService
		elif [[ $MITMPKG == com.pokemod.aegis* ]]; then
			am startservice $MITMPKG/com.pokemod.aegis.services.MappingService
		fi
	elif [[ $MITMPKG == com.sy1vi3* ]]; then
		am force-stop $MITMPKG
		sleep 5
		am start -n $MITMPKG/.MainActivity
	fi
	log -p i -t eMagiskATVService "Services were restarted!"
}

# Adjust the script depending on MITM

check_mitmpkg

# Send a webhook to discord if it's configured

webhook() {
	# Check if discord_webhook variable is set
	if [[ -z "$discord_webhook" ]]; then
		log -p i -t eMagiskATVService "discord_webhook variable is not set. Cannot send webhook."
		return
	fi

	# Check internet connectivity by pinging 8.8.8.8 and 1.1.1.1
	if ! ping -c 1 -W 1 8.8.8.8 >/dev/null && ! ping -c 1 -W 1 1.1.1.1 >/dev/null; then
		log -p i -t eMagiskATVService "No internet connectivity. Skipping webhook."
		return
	fi

	local message="$1"
	local local_ip="$(ip route get 1.1.1.1 | awk '{print $7}')"
	local wan_ip="$(curl -s -k https://ipinfo.io/ip)"
	local mac_address="$(ip link show eth0 | awk '/ether/ {print $2}')"
	local mac_address_nodots="$(ip link show eth0 | awk '/ether/ {print $2}' | tr -d ':')"
	local timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
	local mitm_version="NOT INSTALLED"
	local pogo_version="NOT INSTALLED"
	local agent=""
	local playStoreVersion=""
	local temperature="$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print substr($0, 1, length($0)-3)}')"
	playStoreVersion=$(dumpsys package com.android.vending | grep versionName | head -n 1 | cut -d "=" -f 2 | cut -d " " -f 1)
	android_version=$(getprop ro.build.version.release)
	
	get_deviceName

	# Get mitm version
	mitm_version="$(dumpsys package "$MITMPKG" | awk -F "=" '/versionName/ {print $2}')"

	# Get pogo version
	pogo_version="$(dumpsys package com.nianticlabs.pokemongo | awk -F "=" '/versionName/ {print $2}')"

	# Create a temporary directory to store the files
	local temp_dir="/data/local/tmp/webhook_${timestamp}"
	mkdir "$temp_dir"

	# Retrieve the logcat logs
	logcat -v colors -d > "$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log"
	
	# Create the payload JSON
	local payload_json="{\"username\":\"$mitmDeviceName\",\"content\":\"$message"
	payload_json+="\\n*Device name*: $mitmDeviceName"
	payload_json+="\\nLocal IP: ||$local_ip||"
	payload_json+="\\nWAN IP: ||$wan_ip||"
	payload_json+="\\nmac: $mac_address"
	payload_json+="\\nTemp: $temperature"
	payload_json+="\\nmitm: $MITMPKG"
	payload_json+="\\nmitm version: $mitm_version"
	if [[ -n "$agent" ]]; then
		payload_json+="\\nmitm agent: $agent"
	fi
	payload_json+="\\npogo version: $pogo_version"
	payload_json+="\\nPlay Store version: $playStoreVersion"
	payload_json+="\\nAndroid version: $android_version"
	payload_json+="\"}"

	log -p i -t eMagiskATVService "Sending discord webhook"
	# Upload the payload JSON and logcat logs to Discord
	if [[ $MITMPKG == com.pokemod.atlas* ]]; then
		curl -X POST -k -H "Content-Type: multipart/form-data" -F "payload_json=$payload_json" "$discord_webhook" -F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log" -F "atlaslog=@/data/local/tmp/atlas.log"
	else
		curl -X POST -k -H "Content-Type: multipart/form-data" -F "payload_json=$payload_json" "$discord_webhook" -F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log"
	fi
	# Clean up temporary files
	rm -rf "$temp_dir"
}

# Recheck if $CONFIGFILE exists and has data. Repulls data and checks the RDM connection status.

get_config() {
	if [[ -s $CONFIGFILE ]]; then
		log -p i -t eMagiskATVService "$CONFIGFILE exists and has data. Data will be pulled."
		source $CONFIGFILE
		export rdm_user rdm_password rdm_backendURL discord_webhook timezone autoupdate
	else
		log -p i -t eMagiskATVService "Failed to pull the config file. Make sure $($CONFIGFILE) exists and has the correct data."
	fi
}

autoupdate() {
	# Autoupdate this script
	# emagisk_version=$(grep -o 'versionCode=[0-9]*' /data/adb/modules/emagisk/module.prop -C0 | cut -d '=' -f 2)
	autoupdate_url="https://raw.githubusercontent.com/Astu04/eMagisk/master/custom/ATVServices.sh"
	script_path="/data/adb/modules/emagisk/ATVServices.sh"
	cd /data/local/tmp/

	# Download the updated script
	curl_output=$(curl --silent --show-error --location --insecure --max-time 3 --write-out "%{http_code}" --output updated_script.sh "$autoupdate_url")
	http_status=${curl_output:(-3)}

	# Check if the HTTP status is 200 (OK)
	if [[ $http_status -eq 200 ]]; then
	  # Check if the first line of the updated script is #!/system/bin/sh
	  first_line=$(head -n 1 updated_script.sh)
	  last_line=$(tail -n 2 updated_script.sh|grep "ENDOFFILE")

	  if [[ $first_line = '#!/system/bin/sh' ]] && [[ $last_line = '#ENDOFFILE' ]]; then
		# Compare the content of the downloaded script with the existing script
		if ! cmp -s updated_script.sh "$script_path"; then
		  # Replace the script with the updated version
		  chmod +x updated_script.sh
		  mv updated_script.sh "$script_path"
		  
		  log -p i -t eMagiskATVService "[AUTOUPDATE] ATVServices.sh was auto updated"
		  webhook "[AUTOUPDATE] ATVServices.sh was auto updated"

		  # Run the updated script as a daemon
		  nohup "$script_path" >/dev/null 2>&1 &

		  # Kill the parent process
		  pkill -f "$0"
		else
		  log -p i -t eMagiskATVService  "[AUTOUPDATE] The downloaded script is identical to the existing script."
		  rm -f updated_script.sh
		fi
	  else
		log -p i -t eMagiskATVService  "[AUTOUPDATE] The downloaded script does not have the expected shebang."
		log -p i -t eMagiskATVService  "[AUTOUPDATE] It had: $first_line"
		webhook "[AUTOUPDATE] The downloaded script does not have the expected shebang."
	  fi
	else
	  log -p i -t eMagiskATVService  "[AUTOUPDATE] Failed to download the updated script. HTTP status code: $http_status"
	  webhook "[AUTOUPDATE] Failed to download the updated script. HTTP status code: $http_status"
	fi
}

# Disable playstore alltogether (no auto updates)

# if [ "$(pm list packages -e com.android.vending)" = "package:com.android.vending" ]; then
	# log -p i -t eMagiskATVService "Disabling Play Store"
	# pm disable-user com.android.vending
# fi

# Check if the magiskhide binary exists
if type magiskhide >/dev/null 2>&1; then
	# Enable Magiskhide if not enabled
	if ! magiskhide status; then
		log -p i -t eMagiskATVService "Enabling MagiskHide"
		magiskhide enable
	fi

	# Add Pokemon Go to Magisk hide if it isn't
	if ! magiskhide ls | grep -q -m1 "$POGOPKG"; then
		log -p i -t eMagiskATVService "Adding PoGo to MagiskHide"
		magiskhide add "$POGOPKG"
	fi
fi

# Give all mitm services root permissions

# Check if magisk version is 23000 or less

if [ "$(magisk -V)" -le 23000 ]; then
	for package in "$MITMPKG" com.android.shell; do
		packageUID=$(dumpsys package "$package" | grep userId | head -n1 | cut -d= -f2)
		policy=$(sqlite3 /data/adb/magisk.db "select policy from policies where package_name='$package'")
		if [ "$policy" != 2 ]; then
			log -p i -t eMagiskATVService "$package current policy is $policy. Adding root permissions..."
			if ! sqlite3 /data/adb/magisk.db "DELETE from policies WHERE package_name='$package'" ||
				! sqlite3 /data/adb/magisk.db "INSERT INTO policies (uid,package_name,policy,until,logging,notification) VALUES($packageUID,'$package',2,0,1,1)"; then
				log -p i -t eMagiskATVService "ERROR: Could not add $package (UID: $packageUID) to Magisk's DB."
			fi
		else
			log -p i -t eMagiskATVService "Root permissions for $package are OK!"
		fi
	done
else
	for package in "$MITMPKG" com.android.shell; do
		packageUID=$(dumpsys package "$package" | grep userId | head -n1 | cut -d= -f2)
		policy=$(sqlite3 /data/adb/magisk.db "select policy from policies where package_name='$package'")
		if [ "$policy" != 2 ]; then
			log -p i -t eMagiskATVService "$package current policy is $policy. Adding root permissions..."
			if ! sqlite3 /data/adb/magisk.db "DELETE from policies WHERE package_name='$package'" ||
				! sqlite3 /data/adb/magisk.db "INSERT INTO policies (uid, policy, until, logging, notification) VALUES ($packageUID, 2, 0, 1, 1)"; then
				log -p i -t eMagiskATVService "ERROR: Could not add $package (UID: $packageUID) to Magisk's DB."
			fi
   		else
			log -p i -t eMagiskATVService "Root permissions for $package are OK!"
	  	fi
    	done
fi

# Set mitm mock location permission as ignore

if ! appops get $MITMPKG android:mock_location | grep -qm1 'No operations'; then
	log -p i -t eMagiskATVService "Removing mock location permissions from $MITMPKG"
	appops set $MITMPKG android:mock_location 2
fi

# Disable all location providers

if ! settings get 2>/dev/null; then
	log -p i -t eMagiskATVService "Checking allowed location providers as 'shell' user"
	allowedProviders=".$(su shell -c settings get secure location_providers_allowed)"
else
	log -p i -t eMagiskATVService "Checking allowed location providers"
	allowedProviders=".$(settings get secure location_providers_allowed)"
fi

if [ "$allowedProviders" != "." ]; then
	log -p i -t eMagiskATVService "Disabling location providers..."
	if ! settings put secure location_providers_allowed -gps,-wifi,-bluetooth,-network >/dev/null; then
		log -p i -t eMagiskATVService "Running as 'shell' user"
		su shell -c 'settings put secure location_providers_allowed -gps,-wifi,-bluetooth,-network'
	fi
fi

# Make sure the device doesn't randomly turn off

if [ "$(settings get global stay_on_while_plugged_in)" != 3 ]; then
	log -p i -t eMagiskATVService "Setting Stay On While Plugged In"
	settings put global stay_on_while_plugged_in 3
fi

# Disable package verifier

if [ "$(settings get global package_verifier_enable)" != 0 ]; then
	log -p i -t eMagiskATVService "Disable package verifier"
	settings put global package_verifier_enable 0
fi
if [ "$(settings get global verifier_verify_adb_installs)" != 0 ]; then
	log -p i -t eMagiskATVService "Disable package verifier over adb"
	settings put global verifier_verify_adb_installs 0
fi

# Disable play protect

if [ "$(settings get global package_verifier_user_consent)" != -1 ]; then
	log -p i -t eMagiskATVService "Disable play protect"
	settings put global package_verifier_user_consent -1
fi

# Check if the timezone variable is set

if [ -n "$timezone" ]; then
	# Set the timezone using the variable
	setprop persist.sys.timezone "$timezone"
	log -p i -t eMagiskATVService "Timezone set to $timezone"
else
	log -p i -t eMagiskATVService "Timezone variable not set. Skipping timezone change."
fi

# Check if ADB is disabled (adb_enabled is set to 0)

adb_status=$(settings get global adb_enabled)
if [ "$adb_status" -eq 0 ]; then
	log -p i -t eMagiskATVService "ADB is currently disabled. Enabling it..."
	settings put global adb_enabled 1
fi

# Check if ADB over Wi-Fi is disabled (adb_wifi_enabled is set to 0)

adb_wifi_status=$(settings get global adb_wifi_enabled)
if [ "$adb_wifi_status" -eq 0 ]; then
    log -p i -t eMagiskATVService "ADB over Wi-Fi is currently disabled. Enabling it..."
    settings put global adb_wifi_enabled 1
fi

# Check and set permissions for adb_keys

adb_keys_file="/data/misc/adb/adb_keys"
if [ -e "$adb_keys_file" ]; then
	current_permissions=$(stat -c %a "$adb_keys_file")
	if [ "$current_permissions" -ne 640 ]; then
		log -p i -t eMagiskATVService  "Changing permissions for $adb_keys_file to 640..."
		chmod 640 "$adb_keys_file"
	fi
fi

# Download cacert to use certs instead of curl -k 

cacert_path="/data/local/tmp/cacert.pem"
if [ ! -f "$cacert_path" ]; then
	log -p i -t eMagiskATVService "Downloading cacert.pem..."
	curl -k -o "$cacert_path" https://curl.se/ca/cacert.pem
fi


# Health Service

if result=$(check_mitmpkg); then
	(
		log -p i -t eMagiskATVService "eMagisk: Astu's fork. Starting health check service in 4 minutes... MITM: $MITMPKG"
		counter=0
		rdmDeviceID=1
		log -p i -t eMagiskATVService "Start counter at $counter"
		get_config
		# Check for updates
		if [ "$autoupdate" = "true" ]; then
		  log -p i -t eMagiskATVService "[AUTOUPDATE] Checking for new updates"
		  autoupdate
		else
		  log -p i -t eMagiskATVService "[AUTOUPDATE] Disabled. Skipping"
		fi
		webhook "Booting"
		while :; do  
			sleep $((120+$RANDOM%10))

			# Check MITM config for device name based on the installed MITM 
			get_deviceName

			if [[ "$MITMPKG" == com.pokemod.atlas* ]]; then
				if [[ $(tail -n 1 /data/local/tmp/atlas.log | grep -q "Could not send heartbeat")  ]]; then
    				force_restart
				fi
			fi

			if [[ $counter -gt 3 ]];then
				log -p i -t eMagiskATVService "Critical restart threshold of $counter reached. Rebooting device..."
				webhook "Critical restart threshold of $counter reached. Rebooting device..."
				reboot
				# We need to wait for the reboot to actually happen or the process might be interrupted
				sleep 60 
			fi

			# Check if com.nianticlabs.pokemongo is running
			BUSYBOX_PS_OUTPUT=$(busybox ps | grep -E "com\.nianticlabs\.pokemongo")
			
			# Check if the process is running and adjust I/O priority if found
			if [ -n "$BUSYBOX_PS_OUTPUT" ]; then
				log -p i -t eMagiskATVService "com.nianticlabs.pokemongo is running. Adjusting I/O priority..."
				ionice -p $(pidof com.nianticlabs.pokemongo) -c 0 -n 0
				pids=$(/data/adb/magisk/busybox ps -T | /data/adb/magisk/busybox grep pokemongo | /data/adb/magisk/busybox cut -d' ' -f1 | /data/adb/magisk/busybox xargs)
				for i in $pids; do /data/adb/magisk/busybox chrt -r -p 99 $i & done
			fi

			if [ -n "$rdm_user" ] && [ -n "$rdm_password" ] && [ -n "$rdm_backend" ]; then # In case rdm variables are confiugred
				log -p i -t eMagiskATVService "Started rdm health check!"
				response=$(curl -s -w "%{http_code}" --cacert "$cacert_path" -u "$rdm_user":"$rdm_password" "$rdm_backendURL/api/get_data?show_devices=true&formatted=false")
				statusCode=$(echo "$response" | tail -c 4)
				
				if [ "$statusCode" -ne 200 ]; then
					case "$statusCode" in
						401)
							message="Unauthorized. Check your credentials."
							;;
						404)
							message="Resource not found."
							;;
						500)
							message="Internal Server Error. Check the server logs."
							;;
						*)
							message="Something went wrong with the request. Status code: $statusCode."
							;;
					esac

					log -p i -t eMagiskATVService "RDM statusCode error: $message"
					continue
				fi
				
				rdmInfo=$(echo "$response" | sed '$s/...$//')
				rdmTimestamp=$(echo "$rdmInfo" | jq -r '.data.timestamp')
				lastSeens=$(echo "$rdmInfo" | jq -r '.data.devices[] | select(.uuid | startswith("'"$mitmDeviceName"'")) | .last_seen')

				for lastSeen in $lastSeens
				do
					log -p i -t eMagiskATVService "Found our device! Checking for timestamps..."
					calcTimeDiff=$(( $rdmTimestamp - $lastSeen ))

					if [[ $calcTimeDiff -gt 300 ]]; then
						log -p i -t eMagiskATVService "Last seen at RDM is greater than 5 minutes -> MITM Service will be restarting..."
						force_restart
						led_blue
						counter=$((counter+1))
						log -p i -t eMagiskATVService "Counter is now set at $counter. device will be rebooted if counter reaches 4 failed restarts."
						webhook "Counter is now set at $counter. device will be rebooted if counter reaches 4 failed restarts."
						continue 2
					elif [[ $calcTimeDiff -le 10 ]]; then
						log -p i -t eMagiskATVService "Our device is live!"
						counter=0
						led_red
					else
						log -p i -t eMagiskATVService "Last seen time is a bit off. Will check again later."
						counter=0
						led_red
					fi
				done
				log -p i -t eMagiskATVService "Scheduling next check in 4 minutes..."
			else # As rdm variables aren't configured, we'll check the logs last timestamp
				log -p i -t eMagiskATVService "Started health check!"
				if [[ $MITMPKG == com.pokemod.atlas* ]]; then
					log_path="/data/local/tmp/atlas.log"
				elif [[ $MITMPKG == com.pokemod.aegis* ]]; then
					log_path="/data/local/tmp/aegis.log"
				elif [[ $MITMPKG == com.sy1vi3* ]]; then
					if ! ps -a | grep -v grep | grep "$MITMPKG"; then
						log -p i -t eMagiskATVService "Process $MITMPKG is not alive, starting it"
						am start -n $MITMPKG/.MainActivity
						counter=$((counter+1))
      					else
	   					log -p i -t eMagiskATVService "Process $MITMPKG is alive. No action required."
     					fi
	  				continue
				elif [[ $MITMPKG == com.gocheats.launcher ]]; then
					log_path=$(ls -lt /data/data/com.nianticlabs.pokemongo/cache/Exegg* | grep -E "^-" | head -n 1 | awk '{print $NF}')
				else
					log -p i -t eMagiskATVService "No MITM detected ($MITMPKG?), skipping health check."
					continue
				fi
				# Store the timestamp of the log file into another variable using stat
				timestamp_epoch=$(stat -c "%Y" "$log_path")
				current_time=$(date +%s)

				calcTimeDiff=$(( $current_time - $timestamp_epoch ))
				if [[ $calcTimeDiff -le 120 ]]; then
					log -p i -t eMagiskATVService "The log was modified within the last 120 seconds. No action required."
				else
					log -p i -t eMagiskATVService "The log wasn't modified within the last 120 seconds. Forcing restart of MITM. ts: $timestamp_epoch, time now: $current_time"
					force_restart
					counter=$((counter+1))
				fi
			fi
		done
	) &
else
	log -p i -t eMagiskATVService "MITM isn't installed on this device! The daemon will stop."
fi

#ENDOFFILE

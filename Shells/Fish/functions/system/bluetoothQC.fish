#&help:"Connect Bose QC Earbuds II (auto-repair on key mismatch)"
function connectqc
    set MAC "AC:BF:71:93:45:74"
    set CARD "bluez_card.AC_BF_71_93_45_74"

    if test "$argv[1]" = "--fix"
        echo "🛠 Starting full Bluetooth repair..."

        echo "🔄 Restarting bluetooth service..."
        sudo systemctl restart bluetooth

        echo "🗑 Removing old pairing..."
        bluetoothctl remove $MAC > /dev/null 2>&1

        echo "📡 Starting scan..."
        bluetoothctl scan on > /dev/null 2>&1 &

        echo ""
        echo "⚠ Put Bose QC Earbuds II into pairing mode NOW"
        echo "   Hold button on case until LED blinks blue."
        echo ""

        sleep 8

        echo "🤝 Pairing + trusting + connecting..."

        begin
            echo "pair $MAC"
            sleep 5

            echo "yes"
            sleep 1

            echo "yes"
            sleep 1

            echo "trust $MAC"
            sleep 1

            echo "connect $MAC"
            sleep 5

            echo "exit"
        end | bluetoothctl

        echo "✅ Repair flow completed."
        echo ""
    end

    echo "🎧 Powering on bluetooth..."
    bluetoothctl power on > /dev/null

    echo "🔗 Connecting to Bose QC Earbuds II..."
    bluetoothctl disconnect $MAC > /dev/null 2>&1
    sleep 1

    set connect_out (bluetoothctl connect $MAC 2>&1)

    if echo $connect_out | grep -q "key-missing"
        echo "🔑 Key mismatch detected — re-pairing automatically..."
        echo ""

        sudo systemctl restart bluetooth
        sleep 2

        bluetoothctl remove $MAC > /dev/null 2>&1

        echo "📡 Starting scan..."
        bluetoothctl scan on > /dev/null 2>&1 &
        set scan_pid $last_pid

        echo ""
        echo "⚠ Put Bose QC Earbuds II into pairing mode NOW"
        echo "   Hold button on case until LED blinks blue."
        echo ""

        sleep 8

        kill $scan_pid > /dev/null 2>&1

        echo "🤝 Pairing + trusting + connecting..."

        begin
            echo "pair $MAC"
            sleep 5
            echo "yes"
            sleep 1
            echo "yes"
            sleep 1
            echo "trust $MAC"
            sleep 1
            echo "connect $MAC"
            sleep 5
            echo "exit"
        end | bluetoothctl

        set connect_out (bluetoothctl connect $MAC 2>&1)
    end

    if not echo $connect_out | grep -q "Connection successful"
        echo "❌ Failed to connect. Are the earbuds on and out of the case?"
        echo $connect_out
        return 1
    end

    echo "🎵 Setting audio profile to A2DP..."
    set a2dp_ok false
    for i in 1 2 3 4 5
        if pactl set-card-profile $CARD a2dp-sink 2>/dev/null
            set a2dp_ok true
            break
        end
        sleep 1
    end

    if test "$a2dp_ok" = "false"
        echo "🔄 Profile not set — restarting PipeWire and retrying..."
        systemctl --user restart pipewire pipewire-pulse wireplumber
        sleep 3
        for i in 1 2 3 4 5
            if pactl set-card-profile $CARD a2dp-sink 2>/dev/null
                set a2dp_ok true
                break
            end
            sleep 1
        end
    end

    if test "$a2dp_ok" = "false"
        echo "⚠ Could not set A2DP profile — audio may be low quality"
    else
        set active (pactl list cards | grep -A5 "bluez_card" | grep "Active Profile" | string trim)
        echo "✅ $active"
    end

    echo "✅ Successfully connected to Bose QC Earbuds II!"
end
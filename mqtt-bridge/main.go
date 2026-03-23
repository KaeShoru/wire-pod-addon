package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/fforchino/vector-go-sdk/pkg/vector"
	"github.com/fforchino/vector-go-sdk/pkg/vectorpb"
)

type Config struct {
	Broker            string `json:"broker"`
	Port              int    `json:"port"`
	Username          string `json:"username"`
	Password          string `json:"password"`
	TopicPrefix       string `json:"topic_prefix"`
	Discovery         bool   `json:"discovery"`
	DiscoveryPrefix   string `json:"discovery_prefix"`
	TelemetryInterval int    `json:"telemetry_interval"`
	VectorESN         string `json:"vector_esn"`
}

type VectorStatus struct {
	BatteryPercent   float32 `json:"battery_percent"`
	IsCharging       bool    `json:"is_charging"`
	IsOnCharger      bool    `json:"is_on_charger"`
	Status           string  `json:"status"`
	WiFiSignal       int32   `json:"wifi_signal"`
	Timestamp        int64   `json:"timestamp"`
}

var (
	config Config
	client mqtt.Client
)

func main() {
	configPath := flag.String("config", "/data/mqtt-config.json", "Path to config file")
	flag.Parse()

	// Load config
	data, err := os.ReadFile(*configPath)
	if err != nil {
		log.Fatalf("Failed to read config: %v", err)
	}
	if err := json.Unmarshal(data, &config); err != nil {
		log.Fatalf("Failed to parse config: %v", err)
	}

	log.Printf("Wire-Pod MQTT Bridge starting...")
	log.Printf("Connecting to MQTT broker at %s:%d", config.Broker, config.Port)
	log.Printf("Topic prefix: %s", config.TopicPrefix)

	// Setup MQTT client
	opts := mqtt.NewClientOptions()
	opts.AddBroker(fmt.Sprintf("tcp://%s:%d", config.Broker, config.Port))
	opts.SetClientID("wire-pod-addon")
	opts.SetAutoReconnect(true)
	opts.SetCleanSession(false)

	if config.Username != "" {
		opts.SetUsername(config.Username)
		opts.SetPassword(config.Password)
	}

	opts.OnConnect = func(c mqtt.Client) {
		log.Println("Connected to MQTT broker")
	}

	opts.OnConnectionLost = func(c mqtt.Client, err error) {
		log.Printf("Connection lost: %v", err)
	}

	client = mqtt.NewClient(opts)
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		log.Printf("MQTT connection failed: %v", token.Error())
		log.Println("Continuing without MQTT...")
		// Don't exit - wire-pod should still work
	}

	// Send discovery config if enabled
	if config.Discovery && client.IsConnected() {
		sendDiscoveryConfig()
	}

	// Subscribe to command topics
	if client.IsConnected() {
		subscribeCommands()
	}

	// Start telemetry loop
	if config.VectorESN != "" {
		log.Printf("Will collect telemetry for Vector: %s", config.VectorESN)
		ticker := time.NewTicker(time.Duration(config.TelemetryInterval) * time.Second)
		defer ticker.Stop()

		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

		for {
			select {
			case <-ticker.C:
				if client.IsConnected() {
					publishTelemetry()
				}
			case <-sigChan:
				log.Println("Shutting down MQTT bridge...")
				client.Disconnect(250)
				return
			}
		}
	} else {
		log.Println("No Vector ESN configured, telemetry disabled")
		// Keep running to handle commands
		select {}
	}
}

func publishTelemetry() {
	if config.VectorESN == "" {
		return
	}

	v, err := vector.NewVector(config.VectorESN)
	if err != nil {
		log.Printf("Failed to connect to Vector: %v", err)
		return
	}
	defer v.Conn.Close()

	// Get battery info
	battery, err := v.BatteryState()
	if err != nil {
		log.Printf("Failed to get battery state: %v", err)
		return
	}

	// Get WiFi info (if available)
	var wifiSignal int32 = 0
	if wifiInfo, err := v.Conn.GetWiFiState(v.Ctx, &vectorpb.GetWiFiStateRequest{}); err == nil {
		wifiSignal = wifiInfo.SignalPower
	}

	// Determine status
	status := "idle"
	if battery.IsOnCharger {
		if battery.IsCharging {
			status = "charging"
		} else {
			status = "on_charger"
		}
	}

	telemetry := VectorStatus{
		BatteryPercent:   battery.BatteryPercent,
		IsCharging:       battery.IsCharging,
		IsOnCharger:      battery.IsOnCharger,
		Status:           status,
		WiFiSignal:       wifiSignal,
		Timestamp:        time.Now().Unix(),
	}

	payload, err := json.Marshal(telemetry)
	if err != nil {
		log.Printf("Failed to marshal telemetry: %v", err)
		return
	}

	topic := fmt.Sprintf("%s/status", config.TopicPrefix)
	token := client.Publish(topic, 0, true, payload)
	token.Wait()

	if token.Error() != nil {
		log.Printf("Failed to publish telemetry: %v", token.Error())
	} else {
		log.Printf("Published telemetry: battery=%.0f%% status=%s",
			battery.BatteryPercent*100, status)
	}
}

func subscribeCommands() {
	// Command topic: homeassistant/vector/command
	commandTopic := fmt.Sprintf("%s/command", config.TopicPrefix)
	if token := client.Subscribe(commandTopic, 0, handleCommand); token.Wait() && token.Error() != nil {
		log.Printf("Failed to subscribe to commands: %v", token.Error())
	} else {
		log.Printf("Subscribed to: %s", commandTopic)
	}

	// Eye color topic: homeassistant/vector/set_eyes
	eyesTopic := fmt.Sprintf("%s/set_eyes", config.TopicPrefix)
	if token := client.Subscribe(eyesTopic, 0, handleSetEyes); token.Wait() && token.Error() != nil {
		log.Printf("Failed to subscribe to eye color: %v", token.Error())
	} else {
		log.Printf("Subscribed to: %s", eyesTopic)
	}
}

func handleCommand(c mqtt.Client, m mqtt.Message) {
	cmd := string(m.Payload())
	log.Printf("Received command: %s", cmd)

	if config.VectorESN == "" {
		log.Println("No Vector ESN configured, cannot execute command")
		return
	}

	v, err := vector.NewVector(config.VectorESN)
	if err != nil {
		log.Printf("Failed to connect to Vector: %v", err)
		return
	}
	defer v.Conn.Close()

	switch cmd {
	case "drive_forward":
		log.Println("Command: drive_forward")
		v.DriveStraight(100, 50) // mm, mm/s
	case "drive_backward":
		log.Println("Command: drive_backward")
		v.DriveStraight(-100, 50)
	case "turn_left":
		log.Println("Command: turn_left")
		v.TurnInPlace(90, 45) // degrees, degrees/s
	case "turn_right":
		log.Println("Command: turn_right")
		v.TurnInPlace(-90, 45)
	case "dock":
		log.Println("Command: dock")
		v.Dock()
	case "undock":
		log.Println("Command: undock")
		v.Undock()
	case "anim_hello":
		log.Println("Command: anim_hello")
		v.PlayAnimation("anim_hello")
	case "beep":
		log.Println("Command: beep")
		v.SayText("Beep!")
	default:
		log.Printf("Unknown command: %s", cmd)
	}
}

func handleSetEyes(c mqtt.Client, m mqtt.Message) {
	// Expected payload: {"hue": 120, "saturation": 100}
	var color struct {
		Hue        int `json:"hue"`
		Saturation int `json:"saturation"`
		Intensity  int `json:"intensity,omitempty"`
	}

	if err := json.Unmarshal(m.Payload(), &color); err != nil {
		log.Printf("Failed to parse eye color: %v", err)
		return
	}

	log.Printf("Setting eyes: hue=%d saturation=%d", color.Hue, color.Saturation)

	if config.VectorESN == "" {
		log.Println("No Vector ESN configured, cannot set eye color")
		return
	}

	v, err := vector.NewVector(config.VectorESN)
	if err != nil {
		log.Printf("Failed to connect to Vector: %v", err)
		return
	}
	defer v.Conn.Close()

	// Convert HSV to RGB for Vector
	r, g, b := hsvToRgb(color.Hue, color.Saturation, color.Intensity)
	v.SetEyeColor(uint8(r), uint8(g), uint8(b))
}

func hsvToRgb(h, s, v int) (int, int, int) {
	// Simple HSV to RGB conversion
	if s == 0 {
		return v, v, v
	}

	hh := float64(h) / 60.0
	i := int(hh)
	ff := hh - float64(i)
	p := v * (100 - s) / 100
	q := v * (100 - int(ff*100)*s/100) / 100
	t := v * (100 - (100-int(ff*100))*s/100) / 100

	switch i {
	case 0:
		return v, t, p
	case 1:
		return q, v, p
	case 2:
		return p, v, t
	case 3:
		return p, q, v
	case 4:
		return t, p, v
	default:
		return v, p, q
	}
}

func sendDiscoveryConfig() {
	log.Println("Sending MQTT discovery config...")

	device := map[string]interface{}{
		"identifiers":  []string{"vector_" + config.VectorESN},
		"name":         "Vector Robot",
		"model":        "Anki Vector",
		"manufacturer": "Anki/Digital Dream Labs",
	}

	// Battery sensor
	batteryConfig := map[string]interface{}{
		"name":                "Vector Battery",
		"unique_id":           "vector_battery_" + config.VectorESN,
		"state_topic":         fmt.Sprintf("%s/status", config.TopicPrefix),
		"value_template":      "{{ value_json.battery_percent | float * 100 | int }}",
		"unit_of_measurement": "%",
		"device_class":        "battery",
		"state_class":         "measurement",
		"device":              device,
	}
	publishDiscovery("sensor", "battery", batteryConfig)

	// Status sensor
	statusConfig := map[string]interface{}{
		"name":           "Vector Status",
		"unique_id":      "vector_status_" + config.VectorESN,
		"state_topic":    fmt.Sprintf("%s/status", config.TopicPrefix),
		"value_template": "{{ value_json.status }}",
		"device":         device,
	}
	publishDiscovery("sensor", "status", statusConfig)

	// WiFi signal sensor
	wifiConfig := map[string]interface{}{
		"name":                "Vector WiFi Signal",
		"unique_id":           "vector_wifi_" + config.Vector_ESN,
		"state_topic":         fmt.Sprintf("%s/status", config.TopicPrefix),
		"value_template":      "{{ value_json.wifi_signal }}",
		"unit_of_measurement": "dBm",
		"device_class":        "signal_strength",
		"device":              device,
	}
	publishDiscovery("sensor", "wifi_signal", wifiConfig)

	// Charging binary sensor
	chargingConfig := map[string]interface{}{
		"name":           "Vector Charging",
		"unique_id":      "vector_charging_" + config.VectorESN,
		"state_topic":    fmt.Sprintf("%s/status", config.TopicPrefix),
		"value_template": "{{ 'ON' if value_json.is_charging else 'OFF' }}",
		"device_class":   "battery_charging",
		"device":         device,
	}
	publishDiscovery("binary_sensor", "charging", chargingConfig)

	log.Println("Discovery config sent")
}

func publishDiscovery(component, name string, config map[string]interface{}) {
	topic := fmt.Sprintf("%s/%s/vector/%s/config", config.DiscoveryPrefix, component, name)
	payload, _ := json.Marshal(config)
	token := client.Publish(topic, 0, true, payload)
	token.Wait()
}

package com.hmi.host.hmi_host

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL_NAME = "hmi_host/android_usb_serial/methods"
private const val EVENT_CHANNEL_NAME = "hmi_host/android_usb_serial/events"
private const val ACTION_USB_PERMISSION =
    "com.hmi.host.hmi_host.USB_SERIAL_PERMISSION"

class AndroidUsbSerialBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private data class PortDescriptor(
        val transportName: String,
        val deviceId: Int,
        val portIndex: Int,
    )

    private data class Session(
        val transportId: Int,
        val deviceId: Int,
        val port: UsbSerialPort,
        val ioManager: SerialInputOutputManager,
    )

    private data class PendingConnect(
        val transportId: Int,
        val descriptor: PortDescriptor,
        val baudRate: Int,
        val dataBits: Int,
        val stopBits: Int,
        val parity: Int,
        val flowControl: Int,
        val result: MethodChannel.Result,
    )

    private val usbManager =
        activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<Int, Session>()
    private val pendingConnects = mutableMapOf<Int, PendingConnect>()
    private var eventSink: EventChannel.EventSink? = null

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) {
                    return
                }
                when (intent.action) {
                    ACTION_USB_PERMISSION -> handlePermissionResult(intent)
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> handleDeviceDetached(intent)
                }
            }
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerReceivers()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listPorts" -> result.success(enumeratePorts().map { it.transportName })
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(call, result)
            "write" -> handleWrite(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pendingConnects.values.forEach { pending ->
            pending.result.error("disposed", "Android USB 串口桥接已释放", null)
        }
        pendingConnects.clear()
        sessions.values.toList().forEach { session ->
            closeSession(session.transportId, notifyClosed = false)
        }
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // 忽略重复反注册。
        }
    }

    private fun registerReceivers() {
        val filter =
            IntentFilter().apply {
                addAction(ACTION_USB_PERMISSION)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(receiver, filter)
        }
    }

    private fun enumeratePorts(): List<PortDescriptor> {
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        val descriptors = mutableListOf<PortDescriptor>()
        for (driver in drivers) {
            driver.ports.forEachIndexed { index, _ ->
                descriptors.add(
                    PortDescriptor(
                        transportName = buildTransportName(driver, index),
                        deviceId = driver.device.deviceId,
                        portIndex = index,
                    ),
                )
            }
        }
        return descriptors
    }

    private fun buildTransportName(driver: UsbSerialDriver, portIndex: Int): String {
        val device = driver.device
        val product =
            device.productName
                ?.takeIf { it.isNotBlank() }
                ?: "USB Serial"
        val manufacturer =
            device.manufacturerName
                ?.takeIf { it.isNotBlank() }
                ?: "Unknown"
        val vid = device.vendorId.toString(16).padStart(4, '0').uppercase()
        val pid = device.productId.toString(16).padStart(4, '0').uppercase()
        return "$product [$manufacturer $vid:$pid dev=${device.deviceId} port=$portIndex]"
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val transportId = call.argument<Int>("transportId")
        val portName = call.argument<String>("portName")
        val baudRate = call.argument<Int>("baudRate")
        val dataBits = call.argument<Int>("dataBits")
        val stopBits = call.argument<Int>("stopBits")
        val parity = call.argument<Int>("parity")
        val flowControl = call.argument<Int>("flowControl")
        if (
            transportId == null ||
            portName == null ||
            baudRate == null ||
            dataBits == null ||
            stopBits == null ||
            parity == null ||
            flowControl == null
        ) {
            result.error("invalid_args", "connect 参数不完整", null)
            return
        }

        closeSession(transportId, notifyClosed = false)

        val descriptor =
            enumeratePorts().firstOrNull { it.transportName == portName }
                ?: run {
                    result.error("not_found", "未找到串口设备: $portName", null)
                    return
                }
        val device =
            usbManager.deviceList.values.firstOrNull { it.deviceId == descriptor.deviceId }
                ?: run {
                    result.error("not_found", "USB 设备已断开", null)
                    return
                }

        val pending =
            PendingConnect(
                transportId = transportId,
                descriptor = descriptor,
                baudRate = baudRate,
                dataBits = dataBits,
                stopBits = stopBits,
                parity = parity,
                flowControl = flowControl,
                result = result,
            )
        if (!usbManager.hasPermission(device)) {
            pendingConnects[device.deviceId] = pending
            usbManager.requestPermission(device, buildPermissionIntent(device.deviceId))
            return
        }
        openSession(device, pending)
    }

    private fun buildPermissionIntent(deviceId: Int): PendingIntent {
        val intent =
            Intent(ACTION_USB_PERMISSION).apply {
                `package` = activity.packageName
            }
        val flags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
        return PendingIntent.getBroadcast(activity, deviceId, intent, flags)
    }

    private fun handlePermissionResult(intent: Intent) {
        val device = intent.getParcelableExtraCompat<UsbDevice>(UsbManager.EXTRA_DEVICE)
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        if (device == null) {
            return
        }
        val pending = pendingConnects.remove(device.deviceId) ?: return
        if (!granted) {
            pending.result.error("permission_denied", "USB 权限被拒绝", null)
            return
        }
        openSession(device, pending)
    }

    private fun openSession(device: UsbDevice, pending: PendingConnect) {
        try {
            val driver =
                UsbSerialProber.getDefaultProber()
                    .findAllDrivers(usbManager)
                    .firstOrNull { it.device.deviceId == device.deviceId }
                    ?: throw IllegalStateException("未匹配到 USB Serial 驱动")
            val connection =
                usbManager.openDevice(device)
                    ?: throw IllegalStateException("无法打开 USB 设备")
            val port =
                driver.ports.getOrNull(pending.descriptor.portIndex)
                    ?: throw IllegalStateException("串口端口索引越界")
            port.open(connection)
            port.setParameters(
                pending.baudRate,
                pending.dataBits,
                mapStopBits(pending.stopBits),
                mapParity(pending.parity),
            )
            primeControlLines(port)
            applyFlowControl(port, pending.flowControl)
            val ioManager =
                SerialInputOutputManager(
                    port,
                    object : SerialInputOutputManager.Listener {
                        override fun onNewData(data: ByteArray) {
                            emitEvent(
                                mapOf(
                                    "transportId" to pending.transportId,
                                    "type" to "data",
                                    "data" to data,
                                ),
                            )
                        }

                        override fun onRunError(e: Exception) {
                            emitEvent(
                                mapOf(
                                    "transportId" to pending.transportId,
                                    "type" to "error",
                                    "message" to (e.message ?: "USB 串口读取失败"),
                                ),
                            )
                            closeSession(pending.transportId, notifyClosed = true)
                        }
                    },
                )
            ioManager.start()
            sessions[pending.transportId] =
                Session(
                    transportId = pending.transportId,
                    deviceId = device.deviceId,
                    port = port,
                    ioManager = ioManager,
                )
            pending.result.success(null)
        } catch (e: Exception) {
            pending.result.error("connect_failed", e.message ?: "USB 串口连接失败", null)
            closeSession(pending.transportId, notifyClosed = false)
        }
    }

    private fun primeControlLines(port: UsbSerialPort) {
        // 某些 Android USB-Serial / CDC 设备在主机侧未显式拉起 DTR/RTS 时，
        // 会表现为“可以发送，但对端长期不回数据”。PC 串口工具往往会自动拉线，
        // Android 自定义桥则需要主动兼容。
        runCatching { port.dtr = true }
        runCatching { port.rts = true }
    }

    private fun handleDisconnect(call: MethodCall, result: MethodChannel.Result) {
        val transportId = call.argument<Int>("transportId")
        if (transportId == null) {
            result.error("invalid_args", "disconnect 缺少 transportId", null)
            return
        }
        closeSession(transportId, notifyClosed = true)
        result.success(null)
    }

    private fun handleWrite(call: MethodCall, result: MethodChannel.Result) {
        val transportId = call.argument<Int>("transportId")
        val bytes = call.argument<ByteArray>("bytes")
        if (transportId == null || bytes == null) {
            result.error("invalid_args", "write 参数不完整", null)
            return
        }
        val session =
            sessions[transportId]
                ?: run {
                    result.error("not_connected", "串口未连接", null)
                    return
                }
        try {
            session.ioManager.writeAsync(bytes)
            result.success(bytes.size)
        } catch (e: Exception) {
            closeSession(transportId, notifyClosed = true)
            result.error("write_failed", e.message ?: "USB 串口写入失败", null)
        }
    }

    private fun handleDeviceDetached(intent: Intent) {
        val device = intent.getParcelableExtraCompat<UsbDevice>(UsbManager.EXTRA_DEVICE) ?: return
        val affected =
            sessions.values
                .filter { it.deviceId == device.deviceId }
                .map { it.transportId }
        affected.forEach { transportId ->
            emitEvent(
                mapOf(
                    "transportId" to transportId,
                    "type" to "detached",
                ),
            )
            closeSession(transportId, notifyClosed = false)
        }
    }

    private fun closeSession(transportId: Int, notifyClosed: Boolean) {
        val session = sessions.remove(transportId) ?: return
        try {
            session.ioManager.stop()
        } catch (_: Exception) {
        }
        try {
            session.port.close()
        } catch (_: Exception) {
        }
        if (notifyClosed) {
            emitEvent(
                mapOf(
                    "transportId" to transportId,
                    "type" to "closed",
                ),
            )
        }
    }

    private fun emitEvent(event: Map<String, Any>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun mapStopBits(stopBits: Int): Int =
        when (stopBits) {
            2 -> UsbSerialPort.STOPBITS_2
            3 -> UsbSerialPort.STOPBITS_1_5
            else -> UsbSerialPort.STOPBITS_1
        }

    private fun mapParity(parity: Int): Int =
        when (parity) {
            1 -> UsbSerialPort.PARITY_ODD
            2 -> UsbSerialPort.PARITY_EVEN
            3 -> UsbSerialPort.PARITY_MARK
            4 -> UsbSerialPort.PARITY_SPACE
            else -> UsbSerialPort.PARITY_NONE
        }

    private fun applyFlowControl(port: UsbSerialPort, flowControl: Int) {
        if (flowControl == 0) {
            return
        }
        // 统一保留接口参数，当前 Android USB Host 版本先不强制配置硬件流控，
        // 避免不同驱动实现差异影响 CDC/FTDI/CP210x/CH34x 的基础连通性。
        @Suppress("UNUSED_PARAMETER")
        val ignoredPort = port
    }

    @Suppress("DEPRECATION")
    private inline fun <reified T> Intent.getParcelableExtraCompat(name: String): T? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(name, T::class.java)
        } else {
            getParcelableExtra(name) as? T
        }
}

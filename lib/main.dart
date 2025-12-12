import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guante Traductor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  BluetoothConnection? connection;
  String _status = "Desconectado";
  String _receivedBuffer = "";

  // Variables para la interfaz
  String _letraDetectada = "---";
  String _datosCrudos = "Esperando datos...";
  int _paquetesRecibidos = 0;
  DateTime? _ultimoPaquete;

  bool isConnecting = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // Solicitar todos los permisos necesarios
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // Verificar que todos los permisos estén otorgados
  Future<bool> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    bool connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    bool locationGranted = statuses[Permission.location]?.isGranted ?? false;

    if (!scanGranted || !connectGranted || !locationGranted) {
      setState(() {
        _status = "Permisos denegados";
        isConnecting = false;
      });
      
      // Mostrar diálogo explicativo
      if (mounted) {
        _showPermissionDialog();
      }
      return false;
    }
    return true;
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos Requeridos'),
        content: const Text(
          'Esta app necesita permisos de Bluetooth y Ubicación para funcionar.\n\n'
          'Por favor, ve a Configuración > Aplicaciones > Guante Traductor > Permisos '
          'y activa:\n'
          '• Bluetooth\n'
          '• Ubicación\n'
          '• Dispositivos cercanos'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings(); // Abre la configuración de la app
            },
            child: const Text('Abrir Configuración'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  // Función para conectarse al guante
  void _connectToGlove() async {
    // Verificar permisos ANTES de iniciar el escaneo
    bool hasPermissions = await _checkPermissions();
    if (!hasPermissions) {
      return;
    }

    setState(() {
      isConnecting = true;
      _status = "Buscando 'ESP32test'...";
    });

    try {
      // Verificar que Bluetooth esté habilitado
      bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (isEnabled == false) {
        setState(() {
          _status = "Bluetooth deshabilitado";
          isConnecting = false;
        });
        
        // Pedir habilitar Bluetooth
        bool? enableResult = await FlutterBluetoothSerial.instance.requestEnable();
        if (enableResult == true) {
          _connectToGlove(); // Reintentar
        }
        return;
      }

      bool deviceFound = false;

      // Buscar el dispositivo por nombre
      FlutterBluetoothSerial.instance.startDiscovery().listen(
        (r) {
          String? deviceName = r.device.name;
          print("Dispositivo encontrado: ${deviceName ?? 'Sin nombre'} - ${r.device.address}");
          
          // Buscar específicamente por nombre "ESP32test"
          if (!deviceFound && deviceName != null && deviceName == "ESP32_Guante") {
            print("¡ESP32test encontrado! Conectando...");
            deviceFound = true;
            FlutterBluetoothSerial.instance.cancelDiscovery();
            _connectToDevice(r.device);
          }
        },
        onError: (error) {
          print("Error en el escaneo: $error");
          if (!mounted) return;
          
          String errorMessage = "Error al escanear";
          if (error.toString().toLowerCase().contains("location")) {
            errorMessage = "Se requiere permiso de Ubicación";
          } else if (error.toString().toLowerCase().contains("permission")) {
            errorMessage = "Permisos insuficientes";
          }
          
          setState(() {
            _status = errorMessage;
            isConnecting = false;
          });
        },
        onDone: () {
          if (!deviceFound && mounted) {
            setState(() {
              isConnecting = false;
              _status = "No se encontró 'ESP32test'";
            });
          }
        },
      );

      // Timeout si no encuentra nada en 15 segundos
      Future.delayed(const Duration(seconds: 15), () {
        if (!deviceFound && isConnecting && mounted) {
          FlutterBluetoothSerial.instance.cancelDiscovery();
          setState(() {
            isConnecting = false;
            _status = "Dispositivo no encontrado. ¿Está encendido?";
          });
        }
      });

    } catch (e) {
      print("Error general: $e");
      if (!mounted) return;
      setState(() {
        _status = "Error: ${e.toString().substring(0, 30)}...";
        isConnecting = false;
      });
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _status = "Conectando...";
      });

      connection = await BluetoothConnection.toAddress(device.address);
      
      if (!mounted) return;
      
      String deviceName = device.name ?? "ESP32test";
      setState(() {
        _status = "Conectado a $deviceName";
        isConnecting = false;
      });

      // Escuchar datos entrantes
      connection!.input!.listen(
        _onDataReceived,
        onDone: () {
          if (mounted) {
            setState(() {
              _status = "Desconectado";
              connection = null;
              _letraDetectada = "---";
              _datosCrudos = "Esperando datos...";
            });
          }
        },
        onError: (error) {
          print("Error en conexión: $error");
          if (mounted) {
            setState(() {
              _status = "Error en la conexión";
              connection = null;
            });
          }
        },
      );

    } catch (e) {
      print("Error conectando al dispositivo: $e");
      if (!mounted) return;
      setState(() {
        _status = "Error de conexión";
        isConnecting = false;
        connection = null;
      });
    }
  }

  void _onDataReceived(Uint8List data) {
    // Convertir bytes a String
    String incoming = String.fromCharCodes(data);
    _receivedBuffer += incoming;

    // Procesar todas las líneas completas
    int newlineIndex;
    while ((newlineIndex = _receivedBuffer.indexOf('\n')) != -1) {
      String line = _receivedBuffer.substring(0, newlineIndex);
      _receivedBuffer = _receivedBuffer.substring(newlineIndex + 1);
      if (line.isNotEmpty) {
        _processLine(line);
      }
    }
  }

  void _processLine(String line) {
    line = line.trim();
    print("🔍 Procesando: '$line' (length: ${line.length})");
    
    if (line.startsWith("D") && line.length > 1) {
      // Quitar la 'D' inicial y separar por comas
      String cleanLine = line.substring(1);
      List<String> parts = cleanLine.split(',');

      if (parts.length >= 15) {
        try {
          List<double> v = List<double>.generate(15, (i) {
            if (i < parts.length) {
              return double.tryParse(parts[i].trim()) ?? 0.0;
            }
            return 0.0;
          });

          // Ejecutar la lógica de clasificación
          String letra = _clasificarLetra(v);
          print("🔤 Letra detectada: $letra");

          // Actualizar UI SIEMPRE (no solo cuando cambia la letra)
          if (mounted) {
            setState(() {
              _letraDetectada = letra;
              _paquetesRecibidos++;
              _ultimoPaquete = DateTime.now();
              
              // Mostrar más datos para debug
              _datosCrudos = "Dedo 1: X:${v[0].toStringAsFixed(1)} Y:${v[1].toStringAsFixed(1)} Z:${v[2].toStringAsFixed(1)}\n"
                           "Dedo 2: X:${v[3].toStringAsFixed(1)} Y:${v[4].toStringAsFixed(1)} Z:${v[5].toStringAsFixed(1)}\n"
                           "Dedo 3: X:${v[6].toStringAsFixed(1)} Y:${v[7].toStringAsFixed(1)} Z:${v[8].toStringAsFixed(1)}\n"
                           "Dedo 4: X:${v[9].toStringAsFixed(1)} Y:${v[10].toStringAsFixed(1)} Z:${v[11].toStringAsFixed(1)}\n"
                          "Dedo 5: X:${v[12].toStringAsFixed(1)} Y:${v[13].toStringAsFixed(1)} Z:${v[14].toStringAsFixed(1)}\n"
                           "Paquetes: $_paquetesRecibidos";
            });
          }
        } catch (e) {
          print("❌ Error parseando datos: $e");
        }
      }
    }
  }

  // Lógica de clasificación de letras
  String _clasificarLetra(List<double> v) {
    double X1=v[0]; double Y1=v[1]; double Z1=v[2];
    double X2=v[3]; double Y2=v[4]; double Z2=v[5];
    double X3=v[6]; double Y3=v[7]; double Z3=v[8];
    double X4=v[9]; double Y4=v[10]; double Z4=v[11];
    double X5=v[12]; double Y5=v[13]; double Z5=v[14];

        // Se ha ampliado el rango en +/- 15 para cada intervalo
    if (X1 >= 70.0) { 
    return "H";
}

// 2. B - Pulgar positivo medio, Meñique muy negativo
// Datos B: X1[36 a 39], Z5[-104 a -62]
else if (X1 >= 25.0 && X1 < 50.0 && Z5 <= -50.0) {
    return "B";
}

// 3. C - Pulgar apenas positivo, todos los dedos en "garra" positiva
// Datos C: X1[4 a 12], Z3[37 a 60], Z5[6 a 16]
else if (X1 >= 0.0 && X1 < 25.0 && Z5 >= 0.0) {
    return "C";
}

// 4. D - Pulgar negativo suave, Meñique negativo suave
// Datos D: X1[-12 a -5], Z5[-26 a -20]
else if (X1 >= -20.0 && X1 < -2.0 && Z5 <= -10.0) {
    return "D";
}

// ---------------------------------------------------------
// ZONA DE CONFLICTO 1: E, R, O (Rango medio negativo de X1)
// ---------------------------------------------------------

// 5. E - Se distingue porque el dedo medio (Z3) está más cerrado (valor bajo)
// Datos E: X1[-40 a -26], Z3[10 a 20] -> Las otras tienen Z3 > 35
else if (X1 >= -48.0 && X1 <= -20.0 && Z3 <= 28.0) {
    return "E";
}

// 6. R - Se distingue porque el Meñique (Z5) está cruzado/muy negativo
// Datos R: Z5[-91 a -56] -> O tiene Z5 aprox -20
else if (X1 >= -55.0 && X1 <= -30.0 && Z5 <= -40.0) {
    return "R";
}

// 7. O - Lo que queda en el rango medio (Meñique no tan bajo como R, Medio no tan bajo como E)
// Datos O: X1[-37 a -26], Z3[35 a 55], Z5[-24 a -14]
else if (X1 >= -45.0 && X1 <= -20.0 && Z3 > 30.0 && Z5 > -35.0) {
    return "O";
}

// ---------------------------------------------------------
// ZONA DE CONFLICTO 2: A vs L (Rango muy negativo de X1)
// ---------------------------------------------------------

// 8. L - CANDADO NUEVO
// Datos L: X1[-61 a -51]. 
// DIFERENCIADOR CLAVE: Y4 (Anular Y) es NEGATIVO en L, POSITIVO en A.
// DIFERENCIADOR SECUNDARIO: Y1 (Pulgar Y) es más negativo en L (<-18).
else if (X1 <= -45.0 && (Y4 < 0.0 || Y1 <= -18.0)) {
    return "L";
}

// 9. A - El resto del rango negativo profundo
// Datos A: X1[-69 a -64]. Y4 es Positivo. Z2 es negativo.
else if (X1 <= -55.0 && Z2 <= -10.0) {
    return "A";
}

    return "---";
  }

  void _disconnect() {
    connection?.dispose();
    setState(() {
      connection = null;
      _status = "Desconectado";
      _letraDetectada = "---";
      _datosCrudos = "Esperando datos...";
      _paquetesRecibidos = 0;
      _ultimoPaquete = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Guante Traductor de Señas"),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Estado de conexión con indicador de actividad
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: connection != null ? Colors.green.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Indicador de actividad en tiempo real
                    if (connection != null && _ultimoPaquete != null)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.shade300,
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    Icon(
                      connection != null ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: connection != null ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: connection != null ? Colors.green.shade700 : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // LA LETRA GRANDE - Display principal
              Container(
                width: 250,
                height: 250,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _letraDetectada == "---" 
                      ? Colors.grey.shade100 
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _letraDetectada == "---" 
                        ? Colors.grey.shade300 
                        : Colors.blue.shade400,
                    width: 5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  _letraDetectada,
                  style: TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    color: _letraDetectada == "---" 
                        ? Colors.grey.shade400 
                        : Colors.blue.shade900,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Datos de debug - Ahora con más información
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sensors, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(
                          'Datos de sensores:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _datosCrudos,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Botones de conexión/desconexión
              if (connection == null)
                ElevatedButton.icon(
                  onPressed: isConnecting ? null : _connectToGlove,
                  icon: isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(isConnecting ? "Conectando..." : "Conectar al Guante"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text("Desconectar"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.red.shade300, width: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
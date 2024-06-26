import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class TopicProvider with ChangeNotifier {
  String _topic = ''; // Valor padrão

  String get topic => _topic;

  void setTopic(String newTopic) {
    _topic = newTopic;
    notifyListeners();
  }
}

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => TopicProvider(),
      child: MyApp(),
    ),
  );
}

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Simula um tempo de espera antes de navegar para a próxima tela
    Timer(Duration(seconds: 3), () {
      // Navegar para a próxima tela após 3 segundos
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Cor de fundo da tela de apresentação
      body: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: Image.asset('assets/img.jpg'),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CONEXÃO REMOTA',
      theme: ThemeData(
        primaryColor: Colors.blue,
      ),
      home: SplashScreen(), // Inicia com a SplashScreen
    );
  }
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  static List<Widget> _widgetOptions = <Widget>[
    MyHomePage(),
    IPPage(),
    FerramentasPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex == 0) {
          return true;
        } else {
          setState(() {
            _selectedIndex = 0;
          });
          return false;
        }
      },
      child: Scaffold(
        body: _widgetOptions.elementAt(_selectedIndex),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.public),
              label: 'MQTT',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'IP',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.build),
              label: 'Ferramentas',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.amber[800],
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String server = 'super-author.cloudmqtt.com';
  final int port = 1883;
  final String username = 'tdmstjgu';
  final String password = 'mBv2M7HusSx8';
  String publishTopic = '/Danf/TESTE_2024/V3/Mqtt/Comando';
  String subscribeTopic = '/Danf/TESTE_2024/V3/Mqtt/Feedback';

  MqttServerClient? client;
  bool _connected = false;
  String _receivedMessage = '';
  Timer? _timer;
  TextEditingController _textController = TextEditingController();
  TextEditingController _topicController = TextEditingController();

  final List<String> _suggestions = [
    'TESTE_2024',
    'PRODUCAO_2024',
    'DESENV_2024',
    'QA_2024'
  ];

  @override
  void initState() {
    super.initState();
    final topicProvider = Provider.of<TopicProvider>(context, listen: false);
    _topicController.text = topicProvider.topic;
  }

  @override
  void dispose() {
    _timer?.cancel();
    client?.disconnect();
    _topicController.dispose();
    super.dispose();
  }

  void insertTopic() {
    final topicProvider = Provider.of<TopicProvider>(context, listen: false);
    String topic = _topicController.text.trim();

    // Atualiza os tópicos de publicação e subscrição
    publishTopic = '/Danf/$topic/V3/Mqtt/Comando';
    subscribeTopic = '/Danf/$topic/V3/Mqtt/Feedback';

    // Desconecta o cliente MQTT atual, se estiver conectado
    if (_connected) {
      _timer?.cancel();
      client?.disconnect();
    }

    // Cria e conecta um novo cliente MQTT com os novos tópicos
    _connect();

    // Salva o novo tópico no Provider
    topicProvider.setTopic(topic);
  }

  Future<void> _connect() async {
    client = MqttServerClient(server, '');
    client!.port = port;
    client!.logging(on: true);
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = _onDisconnected;
    client!.onConnected = _onConnected;
    client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client!.connectionMessage = connMessage;

    try {
      await client!.connect(username, password);
    } catch (e) {
      print('Exception: $e');
      client!.disconnect();
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT client connected');
      setState(() {
        _connected = true;
      });
      _startSendingMessages();
    } else {
      print(
          'ERROR: MQTT client connection failed - disconnecting, state is ${client!.connectionStatus!.state}');
      client!.disconnect();
    }

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('Received message: $pt from topic: ${c[0].topic}>');
      setState(() {
        _receivedMessage = pt;
      });
    });

    _subscribeToTopic(subscribeTopic);
  }

  void _subscribeToTopic(String topic) {
    client!.subscribe(topic, MqttQos.atMostOnce);
  }

  void _startSendingMessages() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _publish('SA');
    });
  }

  void _onConnected() {
    print('Connected');
  }

  void _onDisconnected() {
    print('Disconnected');
    setState(() {
      _connected = false;
    });
  }

  void _onSubscribed(String topic) {
    print('Subscribed to $topic');
  }

  Future<void> _publish(String message) async {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message.toUpperCase());
    client!.publishMessage(publishTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  void enviarMensagem(int index, int placa, bool ligado) {
    String mensagemPrefixo = ligado ? 'OFON' : 'OFFF';
    String mensagen_final = '${mensagemPrefixo}C${index + 1}0${placa}';
    print(mensagen_final);
    _publish(mensagen_final);
  }

  Widget _buildConnectionStatus() {
    return Row(
      children: [
        Text(
          'Status: ',
          style: TextStyle(fontSize: 20),
        ),
        Icon(
          _connected ? Icons.circle : Icons.circle,
          color: _connected ? Colors.lightGreen : Colors.red,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CONEXÃO REMOTA'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildConnectionStatus(),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTopicInput(),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      insertTopic();
                    },
                    child: Text('OK'),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        labelText: 'Mensagem',
                      ),
                      onSubmitted: (text) {
                        if (_connected) {
                          _publish(text);
                        }
                      },
                    ),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      if (_connected) {
                        _publish(_textController.text);
                      }
                    },
                    child: Text('Enviar'),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        if (_connected) {
                          _publish('OFAN');
                        }
                      },
                      child: Text('ON'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () {
                        if (_connected) {
                          _publish('OFAO');
                        }
                      },
                      child: Text('OFF'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 1',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 1, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 1, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 2',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 2, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 2, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 3',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 3, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 3, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 4',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 4, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 4, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 5',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 5, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 5, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 6',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 6, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 6, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 7',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 7, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 7, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 8',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 8, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 8, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 9',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                            255, 129, 206, 131)),
                                    onPressed: () {
                                      enviarMensagem(index, 9, true);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Expanded(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor:
                                            Color.fromARGB(255, 255, 106, 95)),
                                    onPressed: () {
                                      enviarMensagem(index, 9, false);
                                    },
                                    child: Text('${index + 1}'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Container(
                width: 100,
                height: 400,
                alignment: Alignment.topLeft,
                decoration: BoxDecoration(),
                child: Text(
                  'Feedback: $_receivedMessage',
                  style: TextStyle(fontSize: 18),
                  textAlign: TextAlign.left,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicInput() {
    return TextFormField(
      controller: _topicController,
      decoration: InputDecoration(
        labelText: 'Tópico',
        suffixIcon: PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: (String value) {
            _topicController.text = value;
          },
          itemBuilder: (BuildContext context) {
            return _suggestions.map<PopupMenuItem<String>>((String value) {
              return PopupMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList();
          },
        ),
      ),
    );
  }
}

class IPPage extends StatefulWidget {
  @override
  _IPPageState createState() => _IPPageState();
}

class _IPPageState extends State<IPPage> {
  String _scanResult = '';
  Timer? _scanTimer;
  Socket? _socket;
  TextEditingController _messageController = TextEditingController();
  String _receivedMessage = '';
  Timer? _sendingSATimer; // Timer para enviar 'SA' a cada segundo
  String _savedTopic = ''; // Variável para armazenar o tópico salvo

  @override
  void initState() {
    super.initState();
    _startScanLoop();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _socket?.close();
    _sendingSATimer?.cancel(); // Cancela o timer de envio de 'SA'
    super.dispose();
  }

  void _startScanLoop() {
    _scanTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _startScan();
    });
  }

  Future<void> _startScan() async {
    RawDatagramSocket? udpSocket;

    try {
      udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udpSocket.broadcastEnabled = true;

      final String broadcastAddress = '255.255.255.255';
      final int port = 5555;

      udpSocket.send(
          utf8.encode('<SI>'), InternetAddress(broadcastAddress), port);

      await Future.delayed(Duration(seconds: 1));

      await for (var datagram in udpSocket) {
        if (datagram == RawSocketEvent.read) {
          Datagram dg = udpSocket.receive()!;
          String response = utf8.decode(dg.data);
          List<String> info = extractInfo(response);
          setState(() {
            _scanResult = info[1]; // IP address
            if (info.isNotEmpty) {
              _savedTopic = info[0]; // Salva o tópico encontrado
            }
          });
          if (_scanResult.isNotEmpty) {
            _scanTimer?.cancel();
            _connectToServer(_scanResult);
          }
          break;
        }
      }
    } catch (e) {
      print('Error during scan: $e');
    } finally {
      udpSocket?.close();
    }
  }

  List<String> extractInfo(String message) {
    RegExp regex = RegExp(r"<([^>]+)><([^>]+)><([^>]+)><([^>]+)>");
    Match? match = regex.firstMatch(message);

    if (match != null) {
      String name = match.group(1)!;
      String ip = match.group(2)!;
      String mac = match.group(3)!;
      String version = match.group(4)!;

      String topico = name.replaceAll('DSCV3', '');

      return [topico, ip, mac, version];
    } else {
      print("A mensagem não está no formato esperado.");
      return [];
    }
  }

  Future<void> _connectToServer(String ip) async {
    try {
      _socket = await Socket.connect(ip, 8080);
      _socket!.listen(
        (data) {
          setState(() {
            _receivedMessage = utf8.decode(data);
          });
        },
        onError: (error) {
          print('Socket error: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro na conexão ⚠️')),
          );
          _socket?.destroy();
        },
        onDone: () {
          print('Server closed connection');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro na conexão ⚠️')),
          );
          _socket?.destroy();
        },
      );
      print('Connected to: $ip');
      _startSendingSA(); // Inicia o envio da mensagem 'SA'
    } catch (e) {
      print('Error connecting to server: $e');
    }
  }

  // Função para enviar a mensagem 'SA' a cada 1 segundo
  void _startSendingSA() {
    _sendingSATimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _sendMessage('SA');
    });
  }

  Future<void> _sendMessage(String message) async {
    if (_socket != null) {
      message = '<$message>'.toUpperCase();
      _socket!.write(message);
      print('Message sent: $message');
    } else {
      print('Socket is not connected');
    }
  }

  // Função para copiar o tópico salvo
  Future<void> captureTopic() async {
    if (_savedTopic.isNotEmpty) {
      Clipboard.setData(ClipboardData(
          text: _savedTopic)); // Copia o tópico para a área de transferência
      print('Tópico copiado: $_savedTopic');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tópico copiado: $_savedTopic'),
        ),
      );
    } else {
      print('Nenhum tópico salvo para copiar');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nenhum tópico salvo para copiar'),
        ),
      );
    }
  }

  void enviarMensagem(int index, int placa, bool ligado) {
    String mensagemPrefixo = ligado ? 'OFON' : 'OFFF';
    String mensagen_final = '${mensagemPrefixo}C${index + 1}0${placa}';
    _sendMessage(mensagen_final);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CONEXÃO VIA IP'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'IP: ${_scanResult.isNotEmpty ? _scanResult : 'Buscando a central...'}',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                ElevatedButton(
                  onPressed: captureTopic,
                  child: Text('Capturar Tópico'),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      labelText: 'Mensagem',
                    ),
                    onSubmitted: (text) {
                      if (_scanResult.isNotEmpty) {
                        _sendMessage(text);
                      }
                    },
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    if (_scanResult.isNotEmpty) {
                      _sendMessage(_messageController.text);
                    }
                  },
                  child: Text('Enviar'),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () {
                      if (_scanResult.isNotEmpty) {
                        _sendMessage('OFAN');
                      }
                    },
                    child: Text('ON'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () {
                      if (_scanResult.isNotEmpty) {
                        _sendMessage('OFAO');
                      }
                    },
                    child: Text('OFF'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 1',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 1, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 1, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 2',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 2, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 2, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 3',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 3, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 3, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 4',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 4, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 4, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 5',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 5, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 5, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 6',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 6, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 6, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 7',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 7, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 7, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 8',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 8, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 8, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(
                          'Placa 9',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Column(
                        children: List.generate(8, (index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(
                                          255, 129, 206, 131)),
                                  onPressed: () {
                                    enviarMensagem(index, 9, true);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor:
                                          Color.fromARGB(255, 255, 106, 95)),
                                  onPressed: () {
                                    enviarMensagem(index, 9, false);
                                  },
                                  child: Text('${index + 1}'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Container(
              width: 100,
              height: 400,
              alignment: Alignment.topLeft,
              decoration: BoxDecoration(),
              child: Text(
                'Feedback: $_receivedMessage',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FerramentasPage extends StatefulWidget {
  @override
  _FerramentasPageState createState() => _FerramentasPageState();
}

class _FerramentasPageState extends State<FerramentasPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Ferramentas'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Criar Cenas'),
              Tab(text: 'ON/OFF'),
              Tab(text: 'Timer'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            CenasPage(), // Página Cenas
            On_offpage(), // Página Teste1 vazia
            TimerPage(), // Página Teste2 vazia
          ],
        ),
      ),
    );
  }
}

class On_offpage extends StatefulWidget {
  @override
  _On_offpagestate createState() => _On_offpagestate();
}

class _On_offpagestate extends State<On_offpage> {
  final TextEditingController _cenaController = TextEditingController();
  List<bool> _checkBoxValuesGreen1 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed1 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen2 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed2 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen3 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed3 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen4 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed4 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen5 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed5 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen6 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed6 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen7 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed7 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen8 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed8 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen9 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed9 = List.generate(8, (index) => false);

  List<bool> _toggleSelection = [true, false];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToggleButtons(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('ON'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('OFF'),
                      ),
                    ],
                    isSelected: _toggleSelection,
                    onPressed: (int index) {
                      setState(() {
                        for (int buttonIndex = 0;
                            buttonIndex < _toggleSelection.length;
                            buttonIndex++) {
                          if (buttonIndex == index) {
                            _toggleSelection[buttonIndex] = true;
                          } else {
                            _toggleSelection[buttonIndex] = false;
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cenaController,
                      decoration: InputDecoration(
                        labelText: 'Comando',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.content_copy),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _cenaController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Comando copiado para a área de transferência'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 1',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen1[index],
                              isCheckedRed: _checkBoxValuesRed1[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen1[index] =
                                      !_checkBoxValuesGreen1[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed1[index] =
                                      !_checkBoxValuesRed1[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 2',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen2[index],
                              isCheckedRed: _checkBoxValuesRed2[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen2[index] =
                                      !_checkBoxValuesGreen2[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed2[index] =
                                      !_checkBoxValuesRed2[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 3',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen3[index],
                              isCheckedRed: _checkBoxValuesRed3[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen3[index] =
                                      !_checkBoxValuesGreen3[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed3[index] =
                                      !_checkBoxValuesRed3[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 4',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen4[index],
                              isCheckedRed: _checkBoxValuesRed4[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen4[index] =
                                      !_checkBoxValuesGreen4[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed4[index] =
                                      !_checkBoxValuesRed4[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 5',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen5[index],
                              isCheckedRed: _checkBoxValuesRed5[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen5[index] =
                                      !_checkBoxValuesGreen5[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed5[index] =
                                      !_checkBoxValuesRed5[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 6',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen6[index],
                              isCheckedRed: _checkBoxValuesRed6[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen6[index] =
                                      !_checkBoxValuesGreen6[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed6[index] =
                                      !_checkBoxValuesRed6[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 7',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen7[index],
                              isCheckedRed: _checkBoxValuesRed7[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen7[index] =
                                      !_checkBoxValuesGreen7[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed7[index] =
                                      !_checkBoxValuesRed7[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 8',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen8[index],
                              isCheckedRed: _checkBoxValuesRed8[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen8[index] =
                                      !_checkBoxValuesGreen8[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed8[index] =
                                      !_checkBoxValuesRed8[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(
                            'Placa 9',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen9[index],
                              isCheckedRed: _checkBoxValuesRed9[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen9[index] =
                                      !_checkBoxValuesGreen9[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed9[index] =
                                      !_checkBoxValuesRed9[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
// Adicione aqui as outras placas conforme necessário...
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _gerarCena,
          child: Text('Gerar Comando'),
        ),
      ),
    );
  }

  void _gerarCena() {
    List<String> cenaParts = [];
    String onOff = _toggleSelection[0] ? "ON" : "OFF";
// Verificando as caixinhas marcadas
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen1, _checkBoxValuesRed1, '1', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen2, _checkBoxValuesRed2, '2', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen3, _checkBoxValuesRed3, '3', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen4, _checkBoxValuesRed4, '4', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen5, _checkBoxValuesRed5, '5', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen6, _checkBoxValuesRed6, '6', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen7, _checkBoxValuesRed7, '7', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen8, _checkBoxValuesRed8, '8', onOff);
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen9, _checkBoxValuesRed9, '9', onOff);

// Construindo a string da cena
    String cenaString = cenaParts.join();

// Atualizando o campo de texto com a cena gerada
    setState(() {
      _cenaController.text = cenaString;
    });

// Exibindo mensagem de cena gerada
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Comando gerado')),
    );
  }

  void _addCheckedPlates(List<String> parts, List<bool> greenFlags,
      List<bool> redFlags, String prefix, String onOff) {
    bool addedCN = false; // Flag para controlar se 'CN' já foi adicionado
    if (onOff == 'OFF') {
      for (int i = 0; i < greenFlags.length; i++) {
        if (greenFlags[i]) {
          String plateNumber = (prefix)
              .padLeft(2, '0'); // Adiciona zero à esquerda se necessário
          if (!addedCN) {
            addedCN = true; // Marca que 'CN' foi adicionado
          }
          parts.add('NCFFC${i + 1}S${plateNumber}');
        }

        if (redFlags[i]) {
          String plateNumber = (prefix)
              .padLeft(2, '0'); // Adiciona zero à esquerda se necessário
          if (!addedCN) {
            addedCN = true; // Marca que 'CN' foi adicionado
          }
          parts.add('NCFFC${i + 1}N${plateNumber}');
        }
      }
    }
    if (onOff == 'ON') {
      for (int i = 0; i < greenFlags.length; i++) {
        if (greenFlags[i]) {
          String plateNumber = (prefix)
              .padLeft(2, '0'); // Adiciona zero à esquerda se necessário
          if (!addedCN) {
            addedCN = true; // Marca que 'CN' foi adicionado
          }
          parts.add('NCONC${i + 1}S${plateNumber}');
        }

        if (redFlags[i]) {
          String plateNumber = (prefix)
              .padLeft(2, '0'); // Adiciona zero à esquerda se necessário
          if (!addedCN) {
            addedCN = true; // Marca que 'CN' foi adicionado
          }
          parts.add('NCONC${i + 1}N${plateNumber}');
        }
      }
    }
  }
}

class TimerPage extends StatefulWidget {
  @override
  _TimerPageState createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  final TextEditingController _cenaController = TextEditingController();
  final TextEditingController _tempoController = TextEditingController();
  List<List<bool>> _checkBoxValues =
      List.generate(9, (index) => List.generate(8, (index) => false));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cenaController,
                      decoration: InputDecoration(
                        labelText: 'Comando',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.content_copy),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _cenaController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Cena copiada para a área de transferência'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: 10),
              TextField(
                controller: _tempoController,
                decoration: InputDecoration(
                  labelText: 'Tempo em minutos',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              SizedBox(height: 10),
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: buildPlateColumn(0)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(1)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(2)),
                    ],
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: buildPlateColumn(3)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(4)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(5)),
                    ],
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: buildPlateColumn(6)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(7)),
                      SizedBox(width: 16),
                      Expanded(child: buildPlateColumn(8)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _gerarCena,
          child: Text('Gerar Comando'),
        ),
      ),
    );
  }

  Widget buildPlateColumn(int plateIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Text(
            'Placa ${plateIndex + 1}',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(height: 5),
        Column(
          children: List.generate(8, (index) {
            return PlateWidget1(
              index: index + 1,
              isChecked: _checkBoxValues[plateIndex][index],
              onTap: () {
                setState(() {
                  _checkBoxValues[plateIndex][index] =
                      !_checkBoxValues[plateIndex][index];
                });
              },
            );
          }),
        ),
      ],
    );
  }

  void _gerarCena() {
    List<String> cenaParts = [];

    // Verificando as caixinhas marcadas
    for (int i = 0; i < _checkBoxValues.length; i++) {
      _addCheckedPlates(cenaParts, _checkBoxValues[i], '${i + 1}');
    }

    // Construindo a string da cena
    String cenaString = cenaParts.join();

    // Adicionando o tempo em minutos no lugar dos zeros com 3 caracteres
    String tempoString = _tempoController.text.padLeft(3, '0');
    if (tempoString.isNotEmpty) {
      cenaString = cenaString.replaceAll('000', tempoString);
    }

    // Atualizando o campo de texto com a cena gerada
    setState(() {
      _cenaController.text = cenaString;
    });

    // Exibindo mensagem de cena gerada
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Comando gerado')),
    );
  }

  void _addCheckedPlates(List<String> parts, List<bool> flags, String prefix) {
    for (int i = 0; i < flags.length; i++) {
      if (flags[i]) {
        String plateNumber =
            (prefix).padLeft(2, '0'); // Adiciona zero à esquerda se necessário
        parts.add('TCC${i + 1}000${plateNumber}');
      }
    }
  }
}

class PlateWidget1 extends StatelessWidget {
  final int index;
  final bool isChecked;
  final VoidCallback onTap;

  const PlateWidget1({
    Key? key,
    required this.index,
    required this.isChecked,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.center,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            margin: EdgeInsets.all(2),
            width: 40,
            height: 30,
            decoration: BoxDecoration(
              color: isChecked ? Colors.yellow : Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: isChecked
                  ? Icon(Icons.check, color: Colors.black)
                  : Text(
                      'C$index',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class CenasPage extends StatefulWidget {
  @override
  _CenasPageState createState() => _CenasPageState();
}

class _CenasPageState extends State<CenasPage> {
  final TextEditingController _cenaController = TextEditingController();
  List<bool> _checkBoxValuesGreen1 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed1 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen2 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed2 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen3 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed3 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen4 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed4 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen5 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed5 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen6 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed6 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen7 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed7 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen8 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed8 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesGreen9 = List.generate(8, (index) => false);
  List<bool> _checkBoxValuesRed9 = List.generate(8, (index) => false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cenaController,
                      decoration: InputDecoration(
                        labelText: 'Cena',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.content_copy),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _cenaController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Cena copiada para a área de transferência'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 1',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen1[index],
                              isCheckedRed: _checkBoxValuesRed1[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen1[index] =
                                      !_checkBoxValuesGreen1[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed1[index] =
                                      !_checkBoxValuesRed1[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 2',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen2[index],
                              isCheckedRed: _checkBoxValuesRed2[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen2[index] =
                                      !_checkBoxValuesGreen2[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed2[index] =
                                      !_checkBoxValuesRed2[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 3',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen3[index],
                              isCheckedRed: _checkBoxValuesRed3[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen3[index] =
                                      !_checkBoxValuesGreen3[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed3[index] =
                                      !_checkBoxValuesRed3[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 4',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen4[index],
                              isCheckedRed: _checkBoxValuesRed4[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen4[index] =
                                      !_checkBoxValuesGreen4[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed4[index] =
                                      !_checkBoxValuesRed4[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 5',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen5[index],
                              isCheckedRed: _checkBoxValuesRed5[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen5[index] =
                                      !_checkBoxValuesGreen5[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed5[index] =
                                      !_checkBoxValuesRed5[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 6',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen6[index],
                              isCheckedRed: _checkBoxValuesRed6[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen6[index] =
                                      !_checkBoxValuesGreen6[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed6[index] =
                                      !_checkBoxValuesRed6[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 7',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen7[index],
                              isCheckedRed: _checkBoxValuesRed7[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen7[index] =
                                      !_checkBoxValuesGreen7[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed7[index] =
                                      !_checkBoxValuesRed7[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 8',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen8[index],
                              isCheckedRed: _checkBoxValuesRed8[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen8[index] =
                                      !_checkBoxValuesGreen8[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed8[index] =
                                      !_checkBoxValuesRed8[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 20.0), // Adicionando padding à esquerda
                          child: Text(
                            'Placa 9',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(height: 5),
                        Column(
                          children: List.generate(8, (index) {
                            return PlateWidget(
                              index: index + 1,
                              isCheckedGreen: _checkBoxValuesGreen9[index],
                              isCheckedRed: _checkBoxValuesRed9[index],
                              onGreenTap: () {
                                setState(() {
                                  _checkBoxValuesGreen9[index] =
                                      !_checkBoxValuesGreen9[index];
                                });
                              },
                              onRedTap: () {
                                setState(() {
                                  _checkBoxValuesRed9[index] =
                                      !_checkBoxValuesRed9[index];
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _gerarCena,
          child: Text('Gerar Cena'),
        ),
      ),
    );
  }

  void _gerarCena() {
    List<String> cenaParts = [];

    // Verificando as caixinhas marcadas
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen1, _checkBoxValuesRed1, '1');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen2, _checkBoxValuesRed2, '2');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen3, _checkBoxValuesRed3, '3');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen4, _checkBoxValuesRed4, '4');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen5, _checkBoxValuesRed5, '5');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen6, _checkBoxValuesRed6, '6');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen7, _checkBoxValuesRed7, '7');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen8, _checkBoxValuesRed8, '8');
    _addCheckedPlates(
        cenaParts, _checkBoxValuesGreen9, _checkBoxValuesRed9, '9');

    // Construindo a string da cena
    String cenaString = cenaParts.join();

    // Atualizando o campo de texto com a cena gerada
    setState(() {
      _cenaController.text = 'CN$cenaString';
    });

    // Exibindo mensagem de cena gerada
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cena gerada')),
    );
  }

  void _addCheckedPlates(List<String> parts, List<bool> greenFlags,
      List<bool> redFlags, String prefix) {
    for (int i = 0; i < greenFlags.length; i++) {
      if (greenFlags[i]) {
        String plateNumber =
            (prefix).padLeft(2, '0'); // Adiciona zero à esquerda se necessário
        parts.add('ONC${i + 1}${plateNumber}');
      }
    }
    for (int i = 0; i < redFlags.length; i++) {
      if (redFlags[i]) {
        String plateNumber =
            (prefix).padLeft(2, '0'); // Adiciona zero à esquerda se necessário
        parts.add('FFC${i + 1}${plateNumber}');
      }
    }
  }
}

class PlateWidget extends StatelessWidget {
  final int index;
  final bool isCheckedGreen;
  final bool isCheckedRed;
  final VoidCallback onGreenTap;
  final VoidCallback onRedTap;

  const PlateWidget({
    required this.index,
    required this.isCheckedGreen,
    required this.isCheckedRed,
    required this.onGreenTap,
    required this.onRedTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: onGreenTap,
            child: Container(
              margin: EdgeInsets.all(2),
              width: 50, // largura aumentada
              height: 25,
              decoration: BoxDecoration(
                color: isCheckedGreen
                    ? Colors.green
                    : Color.fromARGB(255, 227, 255, 226),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  'C$index',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCheckedGreen ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 4),
          GestureDetector(
            onTap: onRedTap,
            child: Container(
              margin: EdgeInsets.all(2),
              width: 50, // largura aumentada
              height: 25,
              decoration: BoxDecoration(
                color: isCheckedRed
                    ? Colors.red
                    : Color.fromARGB(255, 255, 223, 223),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  'C$index',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCheckedRed ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/event.dart';
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  GameballApp gameballApp = GameballApp.getInstance();

  void _testGameball() {
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).then((response){});

    // TODO Replace the values between the braces with the actual values

    gameballApp.init("{api_key}", "{lang}", "{platform}", "{shop}");
    setState(() {

      playerRegistrationCallback(response, error) {
        if(error == null && response != null){
          gameballApp.showProfile(context, "{playerUniqueId}", "{openDetail}", false);
        }
        else{
          // TODO
        }
      }

      CustomerAttributes playerAttributes = CustomerAttributes(
          displayName: "John Doe",
          firstName: "John",
          lastName: "Doe",
          mobileNumber: "0123456789",
          preferredLanguage: "en",
          customAttributes: {
            "{key}": "{value}"
          }
      );

      gameballApp.registerPlayer(
          "{playerUniqueId}",
          "{playerEmail}",
          "{playerMobile}",
          playerAttributes,
          playerRegistrationCallback);

      sendEventCallback(response, error){
        if(error == null && response != null){
          // TODO
        }
        else{
          // TODO
        }
      }

      Event eventBody = Event(
          customerId: "{playerUniqueId}",
          events: {
            "{eventName}": {
              "{prop1}": "{value1}"
            }
          });

      gameballApp.sendEvent(eventBody, sendEventCallback);

    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Gameball Demo',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(
              'Click the FAB below',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _testGameball,
        tooltip: 'Try Gameball',
        child: const Icon(Icons.play_arrow),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

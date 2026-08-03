import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_scanner_example/second/cubit/second_screen_cubit.dart';
import 'package:multi_scanner_example/second/cubit/second_screen_state.dart';
import 'package:multi_scanner_example/third/third.dart';


class SecondScreen extends StatelessWidget {
  static const  route = "/second";
  const SecondScreen({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("2"),),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BlocBuilder<SecondScreenCubit, SecondScreenState>(
              buildWhen: (previousState, state) {
                return state.maybeWhen( onScan: (barcode)=> true, orElse: () => false);
              },
              builder: (context, state) {
                return state.maybeWhen(onScan: (barcode) =>
                    Center(
                      child: Text('Running on: $barcode\n'),
                    ), orElse: () => Container(color: Colors.red,));
              }
          ),
          Center(child: ElevatedButton(child: Text("next"),onPressed: (){
            Navigator.of(context).pushNamed(ThirdScreen.route);
          },)),
          Center(child: ElevatedButton(child: Text("previos"),onPressed: (){
            Navigator.of(context).pop();
          },)),
        ],
      ),
    );
  }
}

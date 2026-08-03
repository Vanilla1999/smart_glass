import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_scanner_example/third/cubit/third_screen_cubit.dart';
import 'package:multi_scanner_example/third/cubit/third_screen_state.dart';

class ThirdScreen extends StatefulWidget {
  static const route = "/third";

  const ThirdScreen({super.key});

  @override
  State<ThirdScreen> createState() => _ThirdScreenState();
}

class _ThirdScreenState extends State<ThirdScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("3"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BlocBuilder<ThirdScreenCubit, ThirdScreenState>(
              buildWhen: (previousState, state) {
            return state.maybeWhen(
                onScan: (barcode) => true, orElse: () => false);
          }, builder: (context, state) {
            return state.maybeWhen(
                onScan: (barcode) => Center(
                      child: Text('Running on: $barcode\n'),
                    ),
                orElse: () => Container(
                      color: Colors.red,
                    ));
          }),
          Center(
              child: ElevatedButton(
            child: Text("Dialog"),
            onPressed: () {
              showAlertDialog(context);
            },
          )),
          Center(
              child: ElevatedButton(
            child: Text("previos"),
            onPressed: () {
              Navigator.of(context).pop();
            },
          )),
        ],
      ),
    );
  }

  showAlertDialog(BuildContext context) {
    context.read<ThirdScreenCubit>().openDialogForScan();

    // set up the button
    Widget okButton = TextButton(
      child: Text("OK"),
      onPressed: () {},
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: StreamBuilder<String>(
        stream:  context.read<ThirdScreenCubit>().barcodeStream,
        builder: (context, snapshot) {
          return Center(
            child: Text('Running on: ${snapshot.data}\n'),
          );
        }
      ),
      content: Text("This is my message."),
      actions: [
        okButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    ).then((_) {
      context.read<ThirdScreenCubit>().closeDialogForScan();
    });
  }
}

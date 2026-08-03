

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:multi_scanner/multi_scanner.dart';

class BluetoothDialogWidget extends StatefulWidget {
  const BluetoothDialogWidget({
    super.key,
    required this.isPortrait,
  });

  final bool isPortrait;

  @override
  State<BluetoothDialogWidget> createState() =>
      _BluetoothDialogWidgetState();
}

class _BluetoothDialogWidgetState extends State<BluetoothDialogWidget> {
  final MultiScannerBluetooth nboBluetooth = MultiScannerBluetooth();
  @override
  void initState() {
    super.initState();
    nboBluetooth.startWork();
    nboBluetooth.startDiscovery();
  }

  @override
  Widget build(BuildContext context) {

    return SizedBox(
      height: 200,
      width: widget.isPortrait ? 300 : 400,
      child: Column(
        children: <Widget>[
          const SizedBox(
            height: 3,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Center(
                  child: Text(
                    "Связанные",
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: Text(
              "Найденные",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 4,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                SizedBox(
                  width: widget.isPortrait ? 150 : 200,
                  child: StreamBuilder<List<BTDevice>>(
                      stream: nboBluetooth.streamOnBTBound,
                      builder: (
                        BuildContext context,
                        AsyncSnapshot<List<BTDevice>> snapshot,
                      ) {
                        // TODO: В отдельный виджет
                        final int length = snapshot.data?.length ?? 0;

                        if (length != 0) {
                          return ListView.separated(
                            itemCount: length,
                            itemBuilder: (BuildContext context, int index) {
                              final BTDevice btDevice = snapshot.data![index];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    nboBluetooth.connect(
                                      btDevice.name,
                                      btDevice.adress,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 10,
                                      right: 10,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                btDevice.name,
                                                style: const TextStyle(
                                                    fontSize: 14),
                                              ),
                                              const SizedBox(
                                                height: 3,
                                              ),
                                              Text(
                                                btDevice.adress,
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 13,
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(40, 40),
                                            padding: EdgeInsets.zero,
                                            backgroundColor: Colors.red,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(50),
                                            ),
                                          ),
                                          onPressed: () {
                                            nboBluetooth.removeBound(
                                              btDevice.name,
                                              btDevice.adress,
                                            );
                                          },
                                          child: Text(
                                            "remove",
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            separatorBuilder: (
                              BuildContext context,
                              int index,
                            ) {
                              return const SizedBox(
                                height: 20,
                              );
                            },
                          );
                        } else {
                          return Center(
                            child: Text(
                              "не найдено",
                            ),
                          );
                        }
                      }),
                ),
                SizedBox(
                  width: widget.isPortrait ? 150 : 200,
                  child: StreamBuilder<List<BTDevice>>(
                      stream: nboBluetooth.streamOnBTFound,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<BTDevice>> snapshot) {
                        final int length = snapshot.data?.length ?? 0;

                        if (length != 0) {
                          return ListView.separated(
                            itemCount: length,
                            itemBuilder: (BuildContext context, int index) {
                              final BTDevice btDevice = snapshot.data![index];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {},
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              btDevice.name,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(
                                              height: 3,
                                            ),
                                            Text(
                                              btDevice.adress,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 13,
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(40, 40),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: Colors.green,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(50),
                                          ),
                                        ),
                                        onPressed: () {
                                          nboBluetooth.createBond(
                                              btDevice.name, btDevice.adress);
                                        },
                                        child: Text(
                                          "pair",
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                            separatorBuilder:
                                (BuildContext context, int index) {
                              return const SizedBox(
                                height: 20,
                              );
                            },
                          );
                        } else {
                          return Center(
                            child: Text(
                              "notFound"),
                          );
                        }
                      }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  @override
  void dispose() {
    nboBluetooth.cancelDiscovery();
    nboBluetooth.stopWork();
    nboBluetooth.clearBTList();
    super.dispose();
  }
}

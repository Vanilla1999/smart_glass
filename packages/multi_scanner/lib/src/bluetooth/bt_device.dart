class BTDevice {
  final String name;
  final String adress;
  final bool enabled;
  final bool isConnected;

  const BTDevice(
      {required this.name,
      required this.adress,
      required this.enabled,
      required this.isConnected});

  BTDevice.fromJson(Map<String, dynamic> json)
      : name = json['deviceName'],
        adress = json['macAdress'],
        enabled = true,
        isConnected = false;
}

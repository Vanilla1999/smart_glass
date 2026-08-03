import 'package:multi_scanner/src/data_matrix_inverse.dart';

class BarcodeSettingsConfig {
  bool? enableQr;
  bool? enableAztec;
  bool? enableEAN8;
  bool? enableEAN13;
  bool? enableEAN13CheckDigitTransmit;
  bool? enableEAN13Plus2;
  bool? enableUPCA;
  bool? enableUPCAPlus2;
  bool? enableUPCACheckDigitTransmit;
  bool? enableUPCATranslateToEAN13;
  bool? enablePDF417;
  bool? enableGS1128;
  bool? enableGS1DataBar;
  bool? enableGS1DataBarExpanded;
  bool? enableGS1Limit;
  DataMatrixInverse? enableDataMatrixInverse;
  bool? enableDataMatrix;
  bool? enableCode11;
  bool? enableCode39;
  int? enableCode39MinLength;
  int? enableCode39MaxLength;
  bool? enableCode128;
  bool? enableIntervaled2of5;
  bool? enableUPCE;

  BarcodeSettingsConfig({
    this.enableQr,
    this.enableAztec,
    this.enableEAN8,
    this.enableEAN13,
    this.enableEAN13CheckDigitTransmit,
    this.enableEAN13Plus2,
    this.enableUPCA,
    this.enableUPCAPlus2,
    this.enableUPCACheckDigitTransmit,
    this.enableUPCATranslateToEAN13,
    this.enablePDF417,
    this.enableGS1128,
    this.enableGS1DataBar,
    this.enableGS1DataBarExpanded,
    this.enableGS1Limit,
    this.enableDataMatrixInverse,
    this.enableDataMatrix,
    this.enableCode11,
    this.enableCode39,
    this.enableCode39MinLength,
    this.enableCode39MaxLength,
    this.enableCode128,
    this.enableIntervaled2of5,
    this.enableUPCE});

  Map<String, dynamic> toJson() =>
      {
        "enableQr": enableQr,
        "enableAztec": enableAztec,
        "enableEAN8": enableEAN8,
        "enableEAN13": enableEAN13,
        "enableEAN13CheckDigitTransmit": enableEAN13CheckDigitTransmit,
        "enableEAN13Plus2": enableEAN13Plus2,
        "enableUPCA": enableUPCA,
        "enableUPCAPlus2": enableUPCAPlus2,
        "enableUPCACheckDigitTransmit": enableUPCACheckDigitTransmit,
        "enableUPCATranslateToEAN13": enableUPCATranslateToEAN13,
        "enablePDF417": enablePDF417,
        "enableGS1128": enableGS1128,
        "enableGS1DataBar": enableGS1DataBar,
        "enableGS1DataBarExpanded": enableGS1DataBarExpanded,
        "enableGS1Limit": enableGS1Limit,
        "enableDataMatrixInverse": enableDataMatrixInverse?.value,
        "enableDataMatrix": enableDataMatrix,
        "enableCode11": enableCode11,
        "enableCode39": enableCode39,
        "enableCode39MinLength": enableCode39MinLength,
        "enableCode39MaxLength": enableCode39MaxLength,
        "enableCode128": enableCode128,
        "enableIntervaled2of5": enableIntervaled2of5,
        "enableUPCE": enableUPCE,
      };
}

enum BarcodeEnum {
  QR_CODE("QR_CODE"),
  CODE_128("CODE_128"),
  PDF_417("PDF_417"),
  EAN_13("EAN_13"),
  EAN_13_CHECK_DIGIT_TRANSMIT("EAN_13_CHECK_DIGIT_TRANSMIT"),// информация о том что это - https://docs.zebra.com/content/tcm/us/en/scanners/general/sm72-ig/symbologies/upc-ean-jan/transmit-upc-a-check-digit.html
  EAN_13_FIVE("EAN_13_FIVE"),
  EAN_13_TWO("EAN_13_TWO"),
  EAN_8("EAN_8"),
  GS1_DATABAR("GS1_DATABAR"),
  CODE_39("CODE_39"),
  UPC_A("UPC_A"),
  UPC_A_TWO("UPC_A_TWO"),
  UPC_A_CHECK_DIGIT_TRANSMIT("UPC_A_CHECK_DIGIT_TRANSMIT"), // информация о том что это - https://docs.zebra.com/content/tcm/us/en/scanners/general/sm72-ig/symbologies/upc-ean-jan/transmit-upc-a-check-digit.html
  UPC_A_FIVE("UPC_A_FIVE"),
  UPC_A_TRANSLATE_EAN13("UPC_A_TRANSLATE_EAN13"),
  GS1_DATABAR_EXPANDED("GS1_DATABAR_EXPANDED"),
  CODE_39_MAXIMUM_LENGTH("CODE_39_MAXIMUM_LENGTH"),
  CODE_39_MINIMUM_LENGTH("CODE_39_MINIMUM_LENGTH"),
  CODE_93("CODE_93"),
  GS1_128("GS1_128"),
  CODABAR("CODABAR"),
  INTERLEAVED_25("INTERLEAVED_25"),
  UPC_E("UPC_E"),
  CODE_11("CODE_11"),
  DATAMATRIX("DATAMATRIX"),
  DATAMATRIX_INVERSE("DATAMATRIX_INVERSE"),// 0 - только обычные, 1 - только инвертированные , 2 - авто // информация о том что это - http://med-zakaz.ru/index.php/ru/48-novosti/111-inversnyj-kod-datamatriks
  GS1_LIMIT("GS1_LIMIT"),
  AZTEC("AZTEC");

  final String value;

  const BarcodeEnum(this.value);
}

import 'package:converterpro/models/currencies.dart';
import 'package:converterpro/models/order.dart';
import 'package:converterpro/models/properties_list.dart';
import 'package:converterpro/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:units_converter/units_converter.dart';

class ConversionsNotifier
    extends AsyncNotifier<Map<PROPERTYX, List<UnitData>>> {
  static final provider =
      AsyncNotifierProvider<
        ConversionsNotifier,
        Map<PROPERTYX, List<UnitData>>
      >(ConversionsNotifier.new);

  @override
  Future<Map<PROPERTYX, List<UnitData>>> build() async {
    final conversionsOrderFuture = ref.watch(
      UnitsOrderNotifier.provider.future,
    );
    // propertiesMapProvider is a synchronous Provider, so watching it here
    // ensures ConversionsNotifier rebuilds whenever exchange rates change.
    final propertiesMap = ref.watch(propertiesMapProvider);

    final conversionsOrder = await conversionsOrderFuture;

    final currenciesCount = propertiesMap[PROPERTYX.currencies]!.getAll().length;
    dPrint(() => '[ConversionsNotifier] Rebuilt with $currenciesCount currencies');

    return conversionsOrder.map(
      (propertyx, orderedUnits) => MapEntry(
        propertyx,
        orderedUnits
            .where(
              (e) => propertiesMap[propertyx]!.getAll().any((u) => u.name == e),
            )
            .map(
              (e) => UnitData(
                propertiesMap[propertyx]!.getUnit(e),
                tec: TextEditingController(),
                property: propertyx,
                textInputType: switch (e) {
                  TEMPERATURE.celsius ||
                  TEMPERATURE.fahrenheit ||
                  TEMPERATURE.delisle ||
                  TEMPERATURE.reamur ||
                  TEMPERATURE.romer => const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  NUMERAL_SYSTEMS.binary ||
                  NUMERAL_SYSTEMS.octal ||
                  NUMERAL_SYSTEMS.decimal =>
                    const TextInputType.numberWithOptions(
                      decimal: false,
                      signed: false,
                    ),
                  NUMERAL_SYSTEMS.hexadecimal => TextInputType.text,
                  _ => const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                },
                validator: switch (e) {
                  TEMPERATURE.celsius ||
                  TEMPERATURE.fahrenheit ||
                  TEMPERATURE.delisle ||
                  TEMPERATURE.reamur ||
                  TEMPERATURE.romer => VALIDATOR.rational,
                  NUMERAL_SYSTEMS.binary => VALIDATOR.binary,
                  NUMERAL_SYSTEMS.octal => VALIDATOR.octal,
                  NUMERAL_SYSTEMS.decimal => VALIDATOR.decimal,
                  NUMERAL_SYSTEMS.hexadecimal => VALIDATOR.hexadecimal,
                  _ => VALIDATOR.rationalNonNegative,
                },
              ),
            )
            .toList(),
      ),
    );
  }

  /// The list of values that has been just cleared out
  List<dynamic>? _savedUnitDataList;

  /// Which [PROPERTYX] has been just cleared
  PROPERTYX? _savedProperty;

  UnitData? _selectedUnit; //unit where the user is writing the value

  /// This function get the value of the unit from currentProperty and update
  /// the currentUnitDataList values. It is used when a conversion changes the
  /// values of the units
  Future<void> _refreshCurrentUnitDataList(PROPERTYX property) async {
    final currentUnitDataList = state.value![property]!;
    final propertiesMap = ref.read(propertiesMapProvider);
    for (UnitData currentUnitData in currentUnitDataList) {
      final currentProperty = propertiesMap[property]!;
      // Guard: skip stale UnitData whose currency is no longer in the property
      // (e.g. after switching to a provider with fewer currencies)
      if (!currentProperty.getAll().any((u) => u.name == currentUnitData.unit.name)) {
        currentUnitData.tec.value = TextEditingValue.empty;
        continue;
      }
      currentUnitData.unit = currentProperty.getUnit(currentUnitData.unit.name);
      if (currentUnitData != _selectedUnit) {
        if (currentUnitData.unit.stringValue == null) {
          currentUnitData.tec.value = TextEditingValue.empty;
        } else {
          currentUnitData.tec.value = TextEditingValue(
            text: currentUnitData.unit.stringValue!,
          );
        }
      }
    }
  }

  /// This function is used to convert all the values from one that has been
  /// modified
  Future<void> convert(UnitData unitData, var value, PROPERTYX property) async {
    final propertiesMap = ref.read(propertiesMapProvider);
    final propertyInstance = propertiesMap[property]!;
    final unitName = unitData.unit.name;
    // Guard: ignore stale UnitData whose currency is no longer in the property
    if (!propertyInstance.getAll().any((u) => u.name == unitName)) {
      return;
    }
    propertyInstance.convert(unitName, value);
    _selectedUnit = unitData;
    await _refreshCurrentUnitDataList(property);
  }

  /// Returns a UnitDataList at a certain page with the current ordering
  /// (usefult with reorder units)
  List<UnitData> getUnitDataListAtPage(PROPERTYX property) =>
      state.value![property]!;

  ///Clears the values of the current page
  Future<void> clearAllValues(PROPERTYX property) async {
    List<UnitData> currentUnitDataList = state.value![property]!;
    if (currentUnitDataList[0].property == PROPERTYX.numeralSystems) {
      _savedUnitDataList = [
        ...currentUnitDataList.map((unitData) => unitData.unit.stringValue),
      ];
    } else {
      _savedUnitDataList = [
        ...currentUnitDataList.map((unitData) => unitData.unit.value),
      ];
    }
    _savedProperty = property;
    await convert(currentUnitDataList[0], null, property);
    // convert doesn't clear a selected textfield
    currentUnitDataList[0].tec.value = TextEditingValue.empty;
  }

  /// Undo the last clear all operation performed
  Future<void> undoClearOperation() async {
    if (_savedUnitDataList != null && _savedProperty != null) {
      List<UnitData> listToUndo = state.value![_savedProperty!]!;
      if (_savedUnitDataList![0] is double) {
        for (int i = 0; i < listToUndo.length; i++) {
          listToUndo[i]
            ..unit.value = _savedUnitDataList![i]
            ..tec.value = TextEditingValue(
              text: _savedUnitDataList![i].toString(),
            );
        }
      } else if (_savedUnitDataList![0] is String) {
        for (int i = 0; i < listToUndo.length; i++) {
          listToUndo[i]
            ..unit.stringValue = _savedUnitDataList![i]
            ..tec.value = TextEditingValue(text: _savedUnitDataList![i]);
        }
      }
      _savedUnitDataList = _savedProperty = null;
    }
  }

  /// Returns true if we should show a snackbar when the user press on the clear
  /// all button (see [undoClearOperation]), false otherwise.
  bool shouldShowSnackbar(PROPERTYX property) =>
      state.value![property]![0].tec.value.text != '';
}

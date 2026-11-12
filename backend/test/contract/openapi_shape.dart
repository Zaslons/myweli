import 'dart:io';

import 'package:yaml/yaml.dart';

/// A small checker of a JSON value against `docs/api/openapi.yaml` — enough
/// of OpenAPI for the shapes this contract writes: `$ref` (schemas and
/// responses), `allOf`, `nullable`, `type`, `enum`, `required`,
/// `properties`, `items`, `format: date-time`, `maxLength` (in code points,
/// as the server counts).
///
/// **Closed by default.** An object schema that declares `properties` (and
/// not `additionalProperties: true`) refuses a key it does not declare:
/// a field the server sends and the contract does not name is a field no
/// generated client can type. The schemas in [opaque] are checked only for
/// being objects — the long-lived payloads (`Provider`, the salon document;
/// `ProviderUser`) whose full conformance is not what these tests are about.
class OpenApiShape {
  OpenApiShape({this.opaque = const {'Provider', 'ProviderUser'}})
    : _doc =
          loadYaml(File('../docs/api/openapi.yaml').readAsStringSync())
              as YamlMap;

  final YamlMap _doc;
  final Set<String> opaque;

  YamlMap get _components => _doc['components'] as YamlMap;

  /// The operation at [path] / [method] (lower case).
  YamlMap operation(String path, String method) {
    final item = (_doc['paths'] as YamlMap)[path];
    if (item is! YamlMap) throw StateError('no path $path in the contract');
    final op = item[method];
    if (op is! YamlMap) throw StateError('no $method $path in the contract');
    return op;
  }

  /// The JSON schema documented for [status] of [method] [path] — the
  /// shared `#/components/responses/*` resolved.
  YamlMap responseSchema(String path, String method, int status) {
    final responses = operation(path, method)['responses'] as YamlMap;
    var r = responses['$status'];
    if (r == null) {
      throw StateError('$method $path does not document $status');
    }
    if (r is YamlMap && r.containsKey(r'$ref')) {
      r = _resolve(r[r'$ref'] as String);
    }
    final content = (r as YamlMap)['content'];
    if (content is! YamlMap) {
      throw StateError('$method $path $status documents no body');
    }
    return (content['application/json'] as YamlMap)['schema'] as YamlMap;
  }

  YamlMap _resolve(String ref) {
    const schemas = '#/components/schemas/';
    const responses = '#/components/responses/';
    if (ref.startsWith(schemas)) {
      return (_components['schemas'] as YamlMap)[ref.substring(schemas.length)]
          as YamlMap;
    }
    if (ref.startsWith(responses)) {
      return (_components['responses'] as YamlMap)[ref.substring(
            responses.length,
          )]
          as YamlMap;
    }
    throw StateError('unsupported \$ref $ref');
  }

  /// Every way [value] departs from [schema]; empty when it conforms.
  List<String> check(Object? value, YamlMap schema, [String at = r'$']) {
    final problems = <String>[];
    _check(value, schema, at, problems);
    return problems;
  }

  /// Every way [value] departs from what [method] [path] documents for
  /// [status].
  List<String> checkResponse(
    String path,
    String method,
    int status,
    Object? value,
  ) => check(value, responseSchema(path, method, status));

  /// [schema] with its `$ref` and `allOf` folded into one object view:
  /// properties and `required` united, `nullable` and
  /// `additionalProperties: true` kept when any part says so.
  ({
    Map<String, YamlMap> properties,
    Set<String> required,
    Set<String> types,
    List<Object?>? enumValues,
    bool nullable,
    bool open,
    bool opaqueObject,
    YamlMap? items,
    String? format,
    int? maxLength,
  })
  _fold(YamlMap schema) {
    final properties = <String, YamlMap>{};
    final required = <String>{};
    final types = <String>{};
    List<Object?>? enumValues;
    var nullable = false;
    var open = false;
    var opaqueObject = false;
    YamlMap? items;
    String? format;
    int? maxLength;

    void visit(YamlMap s) {
      final ref = s[r'$ref'];
      if (ref is String) {
        if (opaque.contains(ref.split('/').last)) {
          opaqueObject = true;
          types.add('object');
          return;
        }
        visit(_resolve(ref));
      }
      for (final part in (s['allOf'] as YamlList?) ?? const []) {
        visit(part as YamlMap);
      }
      if (s['nullable'] == true) nullable = true;
      final type = s['type'];
      if (type is String) types.add(type);
      if (type is YamlList) types.addAll(type.cast<String>());
      if (s['enum'] is YamlList) {
        enumValues = (s['enum'] as YamlList).toList();
      }
      if (s['additionalProperties'] == true) open = true;
      for (final MapEntry(:key, :value)
          in ((s['properties'] as YamlMap?) ?? YamlMap()).entries) {
        properties[key as String] = value as YamlMap;
      }
      required.addAll(((s['required'] as YamlList?) ?? const []).cast());
      if (s['items'] is YamlMap) items = s['items'] as YamlMap;
      if (s['format'] is String) format = s['format'] as String;
      if (s['maxLength'] is int) maxLength = s['maxLength'] as int;
    }

    visit(schema);
    return (
      properties: properties,
      required: required,
      types: types,
      enumValues: enumValues,
      nullable: nullable || types.contains('null'),
      open: open,
      opaqueObject: opaqueObject,
      items: items,
      format: format,
      maxLength: maxLength,
    );
  }

  void _check(Object? value, YamlMap schema, String at, List<String> out) {
    final s = _fold(schema);
    if (value == null) {
      if (!s.nullable) out.add('$at is null, and the contract says not');
      return;
    }
    if (s.enumValues != null && !s.enumValues!.contains(value)) {
      out.add('$at = $value is not one of ${s.enumValues}');
    }
    final types = s.types.difference({'null'});
    if (types.isEmpty) return; // untyped: anything goes
    final ok = types.any(
      (t) => switch (t) {
        'object' => value is Map,
        'array' => value is List,
        'string' => value is String,
        'integer' => value is int,
        'number' => value is num,
        'boolean' => value is bool,
        _ => false,
      },
    );
    if (!ok) {
      out.add('$at = $value (${value.runtimeType}) is not $types');
      return;
    }
    if (value is String) {
      if (s.format == 'date-time' && DateTime.tryParse(value) == null) {
        out.add('$at = $value is not a date-time');
      }
      if (s.maxLength != null && value.runes.length > s.maxLength!) {
        out.add('$at is longer than ${s.maxLength}');
      }
    }
    if (value is List && s.items != null) {
      for (var i = 0; i < value.length; i++) {
        _check(value[i], s.items!, '$at[$i]', out);
      }
    }
    if (value is Map && !s.opaqueObject) {
      for (final key in s.required) {
        if (!value.containsKey(key)) out.add('$at.$key is required, absent');
      }
      for (final MapEntry(:key, value: v) in value.entries) {
        final prop = s.properties[key];
        if (prop != null) {
          _check(v, prop, '$at.$key', out);
        } else if (s.properties.isNotEmpty && !s.open) {
          out.add('$at.$key is sent, and the contract does not name it');
        }
      }
    }
  }
}

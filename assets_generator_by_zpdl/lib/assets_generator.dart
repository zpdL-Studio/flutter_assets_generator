import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/element/element2.dart';
import 'package:assets_annotation_by_zpdl/assets_annotation_by_zpdl.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';

/// Assets Generator
///
/// Read assets in [pubspec.yaml]
/// Generates in form of a structure
class AssetsGenerator extends GeneratorForAnnotation<AssetsAnnotation> {
  const AssetsGenerator();

  @override
  FutureOr<String> generateForAnnotatedElement(
    Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    print('AssetsGenerator -> element: ${element.displayName}');

    if (element is! ClassElement2) {
      throw InvalidGenerationSourceError(
        'Generator cannot target `${element.displayName}`.',
        todo: 'This annotation can only be used on classes.',
        element: element,
      );
    }

    var caseType = CaseType.UNDEFINED;
    final isCamelCase = annotation.read('isCamelCase');
    if (isCamelCase.isBool && isCamelCase.boolValue) {
      caseType = CaseType.CAMEL;
    }

    final isSnakeCase = annotation.read('isSnakeCase');
    if (isSnakeCase.isBool && isSnakeCase.boolValue) {
      caseType = CaseType.SNAKE;
    }
    print('AssetsGenerator caseType : $caseType');

    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync());
    final assets = pubspec['flutter']['assets'] as YamlList;

    final root = <String, dynamic>{};
    for (final assetsPath in assets) {
      var uri = Uri.parse(assetsPath);
      print('AssetsGenerator assetsPath : ${uri.pathSegments}');
      if (uri.pathSegments.isNotEmpty) {
        final name = uri.pathSegments.last;

        if (name.isEmpty) {
          // Directory
          final directory = Directory.fromUri(uri);
          if (directory.existsSync()) {
            var node = _addPath(caseType, root, directory.uri.pathSegments);
            for (final file in directory.listSync()) {
              if (file is File) {
                _addFile(node, file);
              }
            }
          }
        } else {
          // File
          final file = File.fromUri(uri);
          if (file.existsSync() && file.name.trim().isNotEmpty) {
            var node = _addPath(caseType, root, file.parent.uri.pathSegments);
            _addFile(node, file);
          }
        }
      }
    }

    var entries = root.entries;

    while (entries.length <= 1) {
      if (entries.isNotEmpty) {
        final value = entries.first.value;
        if (value is Map<String, dynamic>) {
          entries = value.entries;
          break;
        }
      }
      break;
    }

    final writeClass = <_WriteClass>[];
    final writeFile = <String, List<File>>{};
    final childrenWriteLine = <_WriteLine>[];

    for (final entry in entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final childClassName =
            '_${element.displayName}${_pascalCaseString(key)}';
        childrenWriteLine.addAll(
          _writeCodeBody(
            caseType,
            childClassName,
            value.entries,
            singleInstance: true,
          ),
        );
        writeClass.add(_WriteClass(key, childClassName));
      } else if (value is File) {
        var list = writeFile[value.name];
        if (list == null) {
          list = [value];
          writeFile[value.name] = list;
        } else {
          list.add(value);
        }
      }
    }

    final code = StringBuffer();
    code.writeLine(
      0,
      'extension ${element.displayName}Extension on ${element.displayName} {',
    );
    for (final write in writeClass) {
      code.writeLine(
        1,
        '${write.className} get ${write.key} => ${write.className}();',
      );
    }
    code.writeLine(0, '');
    _writeFiles(
      caseType,
      writeFile,
      (key, value) => code.writeLine(1, 'String get $key => \'$value\';'),
    );

    code.writeLine(0, '}');
    code.writeLine(0, '');

    for (final writeLine in childrenWriteLine) {
      code.writeLine(writeLine.tab, writeLine.str);
    }

    return code.toString();
  }

  Map<String, dynamic> _addPath(
    CaseType caseType,
    Map<String, dynamic> root,
    List<String> pathSegments,
  ) {
    final list =
        pathSegments.toList()..removeWhere((element) => element.isEmpty);

    var node = root;
    for (final pathSegment in list) {
      final pathSegmentCaseString = _caseString(caseType, pathSegment);
      final value = node[pathSegmentCaseString];
      if (value == null) {
        final newNode = <String, dynamic>{};
        node[pathSegmentCaseString] = newNode;
        node = newNode;
      } else if (value is Map<String, dynamic>) {
        node = value;
      } else {
        throw ArgumentError(
          'AssetsGenerator _addPath is not directory $pathSegments',
        );
      }
    }

    return node;
  }

  void _addFile(Map<String, dynamic> node, File file) {
    if (file.existsSync() && file.name.trim().isNotEmpty) {
      node[file.fileName] = file;
    }
  }

  List<_WriteLine> _writeCodeBody(
    CaseType caseType,
    String className,
    Iterable<MapEntry<String, dynamic>> entries, {
    bool singleInstance = false,
  }) {
    final results = <_WriteLine>[];
    final childrenWriteLine = <_WriteLine>[];

    final writeClass = <_WriteClass>[];
    final writeFile = <String, List<File>>{};

    for (final entry in entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final childClassName = className + _pascalCaseString(key);
        childrenWriteLine.addAll(
          _writeCodeBody(caseType, childClassName, value.entries),
        );
        childrenWriteLine.add(_WriteLine.empty());

        writeClass.add(_WriteClass(key, childClassName));
      } else if (value is File) {
        var list = writeFile[value.name];
        if (list == null) {
          list = [value];
          writeFile[value.name] = list;
        } else {
          list.add(value);
        }
      }
    }

    results.add(_WriteLine(0, 'class $className {'));
    if (singleInstance) {
      results.add(
        _WriteLine(1, 'static final $className _instance = $className._();'),
      );
      results.add(_WriteLine(1, 'factory $className() => _instance;'));
      results.add(_WriteLine(1, '$className._();'));
    } else {
      results.add(_WriteLine(1, 'const $className();'));
    }
    results.add(_WriteLine.empty());
    for (final write in writeClass) {
      results.add(
        _WriteLine(
          1,
          'final ${write.className} ${write.key} = const ${write.className}();',
        ),
      );
    }
    results.add(_WriteLine.empty());
    _writeFiles(
      caseType,
      writeFile,
      (key, value) =>
          results.add(_WriteLine(1, 'final String $key = \'$value\';')),
    );
    results.add(_WriteLine(0, '}'));
    results.addAll(childrenWriteLine);
    return results;
  }

  static final RegExp _nonAlphaNumeric = RegExp('[^a-zA-Z0-9_]');
  static final RegExp _alpha = RegExp('[^a-zA-Z]');

  String _caseValueString(String str, String firstLetter) {
    var sb = StringBuffer();

    var nonAlphaNumeric = str.replaceAll(_nonAlphaNumeric, '_');
    if (nonAlphaNumeric.isNotEmpty) {
      sb.write(nonAlphaNumeric[0].replaceAll(_alpha, firstLetter));
      sb.write(nonAlphaNumeric.substring(1));
    }
    return sb.toString();
  }

  String _caseString(CaseType caseType, String str) {
    switch (caseType) {
      case CaseType.UNDEFINED:
        var sb = StringBuffer();

        var nonAlphaNumeric = str.replaceAll(_nonAlphaNumeric, '_');
        if (nonAlphaNumeric.isNotEmpty) {
          sb.write(nonAlphaNumeric[0].replaceAll(_alpha, 'u'));
          sb.write(nonAlphaNumeric.substring(1));
        }
        return _caseValueString(str, 'u');
      case CaseType.CAMEL:
        return _caseCamelString(str);
      case CaseType.SNAKE:
        return _caseSnakeString(str);
    }
  }

  String _caseCamelString(String str) {
    if (str.isNotEmpty) {
      var sb = StringBuffer();
      var upper = false;

      var nonAlphaNumeric = _caseValueString(str, '_');
      for (var i = 0; i < nonAlphaNumeric.length; i++) {
        if (nonAlphaNumeric[i] == '_') {
          upper = true;
        } else if (upper) {
          if (sb.isEmpty) {
            sb.write(nonAlphaNumeric[i].toLowerCase());
          } else {
            sb.write(nonAlphaNumeric[i].toUpperCase());
          }
          upper = false;
        } else {
          sb.write(nonAlphaNumeric[i]);
        }
      }

      return sb.toString();
    }
    return str;
  }

  String _pascalCaseString(String str) {
    if (str.isNotEmpty) {
      var sb = StringBuffer();
      var upper = true;
      var nonAlphaNumeric = _caseValueString(str, '_');

      for (var i = 0; i < nonAlphaNumeric.length; i++) {
        if (nonAlphaNumeric[i] == '_') {
          upper = true;
        } else if (upper) {
          sb.write(nonAlphaNumeric[i].toUpperCase());
          upper = false;
        } else {
          sb.write(nonAlphaNumeric[i]);
        }
      }

      return sb.toString();
    }
    return str;
  }

  String _caseSnakeString(String str) {
    if (str.isNotEmpty) {
      var sb = StringBuffer();
      var nonAlphaNumeric = str.replaceAll(_nonAlphaNumeric, '_');

      for (var i = 0; i < nonAlphaNumeric.length; i++) {
        final upperCase = nonAlphaNumeric[i].toUpperCase();
        final lowerCase = nonAlphaNumeric[i].toLowerCase();
        if (sb.isEmpty && nonAlphaNumeric[i] == '_') {
          continue;
        }

        if (upperCase != lowerCase && upperCase == nonAlphaNumeric[i]) {
          sb.write('_${nonAlphaNumeric[i].toLowerCase()}');
        } else {
          sb.write(nonAlphaNumeric[i]);
        }
      }

      return sb.toString();
    }
    return str;
  }

  void _writeFiles(
    CaseType caseType,
    Map<String, List<File>> files,
    void Function(String key, String value) onWriter,
  ) {
    for (final entry in files.entries) {
      final value = entry.value;
      if (value.isNotEmpty) {
        if (value.length == 1) {
          onWriter(
            _caseString(caseType, value.first.name),
            value.first.path.replaceAll('\\', '/'),
          );
        } else {
          for (final file in value) {
            onWriter(
              _caseString(
                caseType,
                '${file.name}${_pascalCaseString(file.extension)}',
              ),
              file.path.replaceAll('\\', '/'),
            );
          }
        }
      }
    }
  }
}

enum CaseType { UNDEFINED, CAMEL, SNAKE }

extension FileExtension on File {
  String get fileName => path.replaceAll('\\', '/').split('/').last;

  String get name {
    final fileName = this.fileName;
    return fileName.contains('.') ? fileName.split('.').first : fileName;
  }

  String get extension {
    final fileName = this.fileName;
    if (fileName.contains('.')) {
      final sb = StringBuffer();
      final splits = fileName.split('.');
      for (var i = 1; i < splits.length; i++) {
        if (sb.isNotEmpty) {
          sb.write('.');
        }
        sb.write(splits[i]);
      }
      return sb.toString();
    }
    return '';
  }
}

extension StringBufferExtension on StringBuffer {
  void writeLine(int tab, [Object? obj = '']) {
    var write = '';
    for (var i = 0; i < tab; i++) {
      write += '\t';
    }
    write += '$obj';
    writeln(write);
  }
}

class _WriteLine {
  final int tab;
  final String str;

  _WriteLine(this.tab, this.str);

  factory _WriteLine.empty() => _WriteLine(0, '');
}

class _WriteClass {
  final String key;
  final String className;

  _WriteClass(this.key, this.className);
}

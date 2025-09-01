import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'assets_generator.dart';

/// A builder that generates asserts.
Builder assetsByZpdl(BuilderOptions options) =>
    SharedPartBuilder([const AssetsGenerator()], 'assets_by_zpdl');

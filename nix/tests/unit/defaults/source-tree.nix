{ code, files }:
let
  sourceTree = code.nix.tests.source-tree;
  fixtureFiles = files.nix.tests.fixtures.source-tree;
  repository = sourceTree fixtureFiles.valid.__path;
in
{
  testSourceTreeImportsPureFactoriesWithoutForcingUnusedExpressions = {
    expr = {
      function = builtins.isFunction repository.code.factory;
      result = repository.code.factory { value = 41; };
      unusedExpressionIndexed = repository.code ? unselected;
    };
    expected = {
      function = true;
      result = 42;
      unusedExpressionIndexed = true;
    };
  };
  testSourceTreeExposesNestedAssetsThroughAttributes = {
    expr = {
      assetIsPath = builtins.isPath repository.files.nested."payload.json";
      rootIsPath = builtins.isPath repository.files.__path;
      nestedDirectoryIsPath = builtins.isPath repository.files.nested.__path;
      payload = builtins.fromJSON (builtins.readFile repository.files.nested."payload.json");
      nestedDirectory = repository.files.nested.__path == fixtureFiles.valid.nested.__path;
    };
    expected = {
      assetIsPath = true;
      rootIsPath = true;
      nestedDirectoryIsPath = true;
      payload.message = "nested asset";
      nestedDirectory = true;
    };
  };
  testSourceTreeKeepsCollidingFilesAndDirectoryChildrenAccessible = {
    expr =
      let
        collision = sourceTree fixtureFiles.collision.__path;
      in
      {
        factory = collision.code.thing.__file { value = 40; };
        fileIsPath = builtins.isPath collision.files.thing.__file;
        directoryIsPath = builtins.isPath collision.files.thing.__path;
        childAsset = builtins.readFile collision.files.thing."data.txt";
      };
    expected = {
      factory = 42;
      fileIsPath = true;
      directoryIsPath = true;
      childAsset = "Collision fixture data.\n";
    };
  };
}

using System.Text;
using LibBundle3;
using LibBundle3.Records;

/// <summary>
/// Batch extractor for 特效补丁 assets.
/// Reads a list of file paths and extracts them from a Bundles2 index,
/// preserving directory structure under the output directory.
/// </summary>
///
/// Usage:
///   AssetExtractor <index.bin> <paths.txt> <output_dir>
///
///   index.bin   — Path to _.index.bin (易泥-modified)
///   paths.txt   — Newline-separated list of file paths to extract
///   output_dir  — Root directory where extracted files are written
///                 (relative path from the bundle is preserved)

if (args.Length < 3)
{
    Console.Error.WriteLine("Usage: AssetExtractor <index.bin> <paths.txt> <output_dir>");
    return 1;
}

var indexPath = args[0];
var pathsFile = args[1];
var outputRoot = args[2];

if (!File.Exists(indexPath)) { Console.Error.WriteLine($"Index not found: {indexPath}"); return 1; }
if (!File.Exists(pathsFile)) { Console.Error.WriteLine($"Paths file not found: {pathsFile}"); return 1; }

// Read target paths
var targetPaths = new List<string>();
foreach (var line in File.ReadAllLines(pathsFile))
{
    var trimmed = line.Trim();
    if (trimmed.Length > 0)
        targetPaths.Add(trimmed);
}

Console.WriteLine($"Loading index: {indexPath}");
var bundles2Dir = Path.GetDirectoryName(Path.GetFullPath(indexPath))!;
var factory = new DriveBundleFactory(bundles2Dir);
using var index = new LibBundle3.Index(indexPath, false, factory);
var failed = index.ParsePaths();
if (failed > 0)
    Console.WriteLine($"Warning: {failed} paths failed to parse");

Console.WriteLine($"Files in index: {index.Files.Count}");
Console.WriteLine($"Target paths:   {targetPaths.Count}");

// Build lookup: normalize path separators for matching
var pathLookup = new Dictionary<string, FileRecord>(StringComparer.OrdinalIgnoreCase);
foreach (var fr in index.Files.Values)
{
    if (!string.IsNullOrEmpty(fr.Path))
        pathLookup[fr.Path.Replace('\\', '/')] = fr;
}

int extracted = 0;
int notFound = 0;
var errors = new List<string>();

// Group by bundle for efficient processing
var toExtract = new List<(string path, FileRecord fr)>();
foreach (var tp in targetPaths)
{
    var normalized = tp.Replace('\\', '/');
    if (pathLookup.TryGetValue(normalized, out var fr))
        toExtract.Add((normalized, fr));
    else
    {
        notFound++;
        errors.Add($"NOT FOUND: {normalized}");
    }
}

var byBundle = toExtract.GroupBy(x => x.fr.BundleRecord);

Console.WriteLine($"Found {toExtract.Count} files in {byBundle.Count()} bundles");

foreach (var group in byBundle)
{
    if (!group.Key.TryGetBundle(out var bundle))
    {
        foreach (var item in group)
            errors.Add($"FAILED (bundle open): {item.path}");
        continue;
    }

    using (bundle)
    {
        foreach (var (path, fr) in group)
        {
            try
            {
                var data = fr.Read(bundle).ToArray();

                var outputPath = Path.Combine(outputRoot, path.Replace('/', Path.DirectorySeparatorChar));
                var outputDir = Path.GetDirectoryName(outputPath);
                if (!string.IsNullOrEmpty(outputDir))
                    Directory.CreateDirectory(outputDir!);

                File.WriteAllBytes(outputPath, data);
                extracted++;

                if (extracted % 100 == 0)
                    Console.WriteLine($"  {extracted}/{toExtract.Count} extracted...");
            }
            catch (Exception ex)
            {
                errors.Add($"FAILED: {path} — {ex.GetType().Name}: {ex.Message}");
            }
        }
    }
}

Console.WriteLine($"Done: {extracted} extracted, {notFound} not found, {errors.Count - notFound} failed");

if (errors.Count > 0)
{
    Console.WriteLine();
    Console.WriteLine("Errors:");
    foreach (var err in errors)
        Console.WriteLine($"  {err}");
}

return errors.Count == notFound ? 0 : 1;

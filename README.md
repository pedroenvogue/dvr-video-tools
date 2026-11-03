# DVR Video Tools

Two Bash utilities for working with DVR/CCTV recordings stored as `.dat` files: batch conversion to MP4, optional separation of a four-camera composite image, and playback-speed troubleshooting using candidate frame rates.

The scripts automate FFmpeg and FFprobe commands. They run locally and do not upload recordings anywhere. A `.dat` extension does not identify a single video format: these tools work only when FFmpeg can read the recording and write the selected streams into MP4.

## Files and purpose

| File | Purpose | Input | Output |
| --- | --- | --- | --- |
| `ConvertParallel.sh` | Process multiple recordings using GNU Parallel | Lowercase `.dat` files below the current working directory | MP4 files under `output/converted/`, or four cropped videos per recording under `output/extracted_cameras/` |
| `fix_dvr_framerate.sh` | Try four playback frame rates for one recording | One filename in a chosen directory | Four candidate MP4 files under that directory's `output_fixed/` |
| `.gitignore` | Keep recordings and generated videos out of normal Git staging | Common recording and output filenames | Git ignore rules; it does not remove already tracked files |

## Requirements and installation

Use Bash on Linux, such as Ubuntu. Windows users can use an Ubuntu environment in WSL, with paths accessible inside WSL. These are Bash scripts; do not run them with `sh`, Command Prompt, or PowerShell directly.

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install ffmpeg parallel git
```

The `ffmpeg` package normally supplies both `ffmpeg` and `ffprobe`. The `parallel` command must be **GNU Parallel**. Check the installation:

```bash
ffmpeg -version
ffprobe -version
parallel --version
bash --version
```

Make the scripts executable, or invoke them explicitly with Bash:

```bash
chmod +x ConvertParallel.sh fix_dvr_framerate.sh
```

Before batch processing, inspect a representative recording:

```bash
ffprobe -hide_banner "/path/to/recordings/00000000.dat"
```

If FFprobe cannot identify usable video, changing the extension alone will not solve the problem. A vendor export tool, different demuxer, or separate recovery workflow may be necessary.

## Quick start

Keep the scripts in a tools directory and run the batch converter from the recording directory:

```bash
cd "/path/to/recordings"
bash "/path/to/dvr-video-tools/ConvertParallel.sh"
```

For frame-rate testing:

```bash
bash "/path/to/dvr-video-tools/fix_dvr_framerate.sh" "/path/to/recordings" "00000000.dat"
```

Replace the example paths with your actual locations. Work on copies of recordings and keep the originals until the outputs have been checked.

## 1. ConvertParallel.sh in detail

### Normal conversion mode

The default mode is `convert`, with four simultaneous jobs. The script finds lowercase `.dat` files recursively beneath the **current working directory**, excludes the top-level `output/` directory, and sends the filenames to GNU Parallel.

Each worker calls `process_file`. That function removes the leading `./` from the discovered path, changes the filename suffix to `.mp4`, creates the destination's parent directory, and runs:

```bash
ffmpeg -nostdin -n -hide_banner -loglevel error -i "$file" -c copy "$outfile"
```

| Option | Meaning in this command |
| --- | --- |
| `-i` | Identifies the source recording |
| `-c copy` | Copies selected encoded streams without decoding and re-encoding |
| `-n` | Refuses to overwrite an existing output |
| `-nostdin` | Disables interactive terminal input |
| `-hide_banner` | Hides FFmpeg's startup banner |
| `-loglevel error` | Displays errors while suppressing most routine FFmpeg messages |

This operation is usually called **remuxing**. It changes the container while copying compressed media packets. It does not improve image quality, repair missing frames, or necessarily make unsupported codecs playable in every device.

The command has no explicit `-map`, so FFmpeg performs automatic stream selection. Do not assume every video, audio, subtitle, or proprietary metadata stream is retained. In particular, a multi-stream DVR recording is different from a single image containing four camera views.

### Folder preservation

| Input relative to the recording directory | Converted output |
| --- | --- |
| `00000000.dat` | `output/converted/00000000.mp4` |
| `Monday/00000001.dat` | `output/converted/Monday/00000001.mp4` |
| `Gate/Evening/clip.dat` | `output/converted/Gate/Evening/clip.mp4` |

Identical basenames in separate source folders therefore receive separate output paths. The script does not preserve source filesystem dates or guarantee preservation of DVR timestamps or other metadata.

### Parallel processing

Set the job count for an individual run:

```bash
PARALLEL_JOBS=2 bash "/path/to/dvr-video-tools/ConvertParallel.sh"
```

The value must be a positive integer. Four jobs means up to four separate file-processing commands at a time; each FFmpeg process may itself use multiple threads. Start with one or two jobs when storage is slow or when cropping many videos. More jobs do not guarantee faster completion.

The functions are defined before `export -f` makes them available to worker shells. The script sets `SHELL` to Bash for GNU Parallel. Filenames travel through `find -print0` and `parallel -0`, so spaces, quotes, and embedded newline characters are not used as filename separators.

### Optional four-camera extraction

If a recording contains a **single video image laid out as an equal 2×2 grid**, run:

```bash
MODE=extract PARALLEL_JOBS=1 bash "/path/to/dvr-video-tools/ConvertParallel.sh"
```

`extract_cameras` splits the first video stream into four filter branches and crops one quadrant from each:

| Output suffix | Position | Crop expression: width, height, x, y |
| --- | --- | --- |
| `_cam1.mp4` | Top left | `iw/2:ih/2:0:0` |
| `_cam2.mp4` | Top right | `iw/2:ih/2:iw/2:0` |
| `_cam3.mp4` | Bottom left | `iw/2:ih/2:0:ih/2` |
| `_cam4.mp4` | Bottom right | `iw/2:ih/2:iw/2:ih/2` |

For `Monday/clip.dat`, the files are `output/extracted_cameras/Monday/clip_cam1.mp4` through `clip_cam4.mp4`.

`iw` and `ih` represent the source image dimensions. A 1920×1080 composite normally produces quadrants of 960×540, subject to pixel-format alignment. Each output contains only its selected video filter result; audio is not mapped. Cropping requires re-encoding, and FFmpeg chooses the default available MP4 video encoder because the script does not specify one. Encoding quality, file size, and speed therefore depend on the installed build and defaults.

This feature crops visible quadrants. It does not discover camera channels, reconstruct missing camera detail, or demultiplex four separate streams. Unequal panels, borders, unusual dimensions, and non-grid layouts need adjusted crop settings. If an extraction fails, some partial camera outputs may remain; inspect or remove those before retrying.

### Completion and repeated runs

A success message is printed only when the corresponding FFmpeg command succeeds. Batch errors produce a nonzero exit status. Existing output files cause that job to fail because overwriting is disabled; they are not silently treated as successful conversions. Choose a fresh output location or deliberately remove the relevant generated files before rerunning.

An empty search runs no conversion jobs and finishes successfully. The script searches only lowercase `.dat` filenames, does not follow directory symlinks, and processes files individually rather than joining them together.

## 2. fix_dvr_framerate.sh in detail

### Purpose and arguments

Use this script when a readable recording appears to play too quickly or too slowly. It creates comparison candidates; it does not automatically determine the correct frame rate.

```bash
bash fix_dvr_framerate.sh [recording-directory] [filename]
```

| Argument | Default | Description |
| --- | --- | --- |
| First | `.` | Directory containing the recording |
| Second | `00000000.dat` | Filename, resolved after entering that directory |

With no arguments, it tests `00000000.dat` in the current directory. The hardcoded drive path from the original upload has been replaced by these arguments. The directory change and input-file checks must succeed before processing starts.

### Analysis with FFprobe

The script reads `r_frame_rate` from the first video stream and the container's reported duration. A result such as `25/1` is a fraction representing 25 frames per second. These values describe what FFprobe reports; they are not proof of the original recording's actual capture timing. A missing duration may appear as `N/A`.

### Candidate generation

It tests these fixed values:

| Candidate rate | Output filename |
| --- | --- |
| 12.5 fps | `output_fixed/test_12.5fps.mp4` |
| 15 fps | `output_fixed/test_15fps.mp4` |
| 25 fps | `output_fixed/test_25fps.mp4` |
| 30 fps | `output_fixed/test_30fps.mp4` |

For each rate, it runs the equivalent of:

```bash
ffmpeg -nostdin -y -hide_banner -loglevel error -r 25 -i "00000000.dat" -c copy "output_fixed/test_25fps.mp4"
```

The placement of `-r` **before** `-i` makes it an input timing option. It asks FFmpeg to interpret input video using the supplied constant frame rate. With stream copying, no new visual detail is generated; the effect on timestamps and playback must be checked for the actual format and FFmpeg build. Existing audio timing may not remain synchronized.

After a successful candidate is written, FFprobe reads its new duration. If generation or inspection fails, the script reports the error, continues to other rates, and returns a nonzero exit status at the end.

**The candidate filenames are reused and `-y` overwrites them.** Save a chosen result under a separate name before testing another recording in the same directory.

### Choosing a rate

Play every successful candidate. Compare movement, a visible recording clock, or an independently known event duration. A plausible walking speed alone is weak evidence. If all candidates still look incorrect, the problem may involve variable timing, corruption, missing frames, or an untested rate.

For a constant-frame-rate sequence, a useful estimate is:

`duration in seconds ≈ number of video frames ÷ frames per second`

For example, 1,500 frames at 25 fps span about 60 seconds; at 12.5 fps they span about 120 seconds. This estimate ignores irregular timestamps and audio duration.

Once a rate is verified, apply the same timing approach to another file manually, using a new output name:

```bash
ffmpeg -nostdin -n -r 25 -i "another_recording.dat" -c copy "another_recording_25fps.mp4"
```

The frame-rate test does not automatically change the batch converter's timing settings.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| `parallel: command not found` | Install GNU Parallel using `sudo apt install parallel`. |
| Exported function is not found | Run with Bash and use the prepared version, which exports functions after defining them. |
| `Invalid data found when processing input` | Inspect the source with FFprobe; the DVR format may be unsupported, encrypted, damaged, or unrelated to video. |
| MP4 rejects a codec or header | Stream copying requires MP4-compatible selected streams; a different container or deliberate re-encoding may be required. |
| No files are processed | Confirm the working directory and lowercase `.dat` extension. |
| Output already exists | Batch mode refuses overwrites; inspect existing results before deleting or moving them. |
| Playback remains wrong | Try timing verification against a known event; candidate rates do not repair corruption. |
| Camera views are incorrect | Extraction assumes an equal 2×2 composite in the first video stream. |
| CPU usage is high | Reduce `PARALLEL_JOBS`, especially during re-encoding for crops. |
| Crop/encoder dimension error | Inspect source dimensions and pixel format; adjust crops or encoding settings. |
| `Permission denied` | Invoke using `bash scriptname.sh`, or add execute permission with `chmod +x`. |
| Some outputs exist after a failure | They may be incomplete. Inspect them; the scripts do not automatically clean partial files. |

Check the last command's exit status immediately afterward:

```bash
echo $?
```

Zero means the script reported success. It does not certify that the chosen speed is correct or that every original stream was preserved. Watch representative outputs and compare durations before deleting any source data.

## Changes from the uploaded originals

The prepared copies keep the original filenames and main purposes, with these changes:

- Function exports now follow their definitions; GNU Parallel workers explicitly use Bash.
- Batch input uses null delimiters, excludes generated `output/`, and handles an empty search.
- Camera output paths no longer repeat source folder names; an explicit four-way split feeds the crop filters.
- `MODE` and `PARALLEL_JOBS` allow configuration without commenting and uncommenting commands.
- FFmpeg success is checked before printing success messages; failures propagate to the exit status.
- Batch outputs use explicit no-overwrite behavior and noninteractive FFmpeg input.
- Frame-rate testing accepts a directory and filename, replacing the original machine-specific path.
- Dependency, directory, and file checks stop processing when prerequisites are missing.
- The unused `output/by_folder/` directory is no longer created.

The original uploaded attachments have not been overwritten. These prepared copies should still be tested against representative recordings from the actual DVR.

## Validation of the prepared copies

Bash syntax checks passed. Tests using a synthetic H.264 recording verified remuxing, nested paths containing spaces and quotation marks, refusal to overwrite, four camera outputs at the expected dimensions, all four frame-rate candidates, and errors for missing inputs and directories. Batch worker functions were also invoked in child Bash processes to check function exporting.

GNU Parallel was not installed in the preparation environment, so actual simultaneous batch scheduling was not tested. No recording from the target DVR was included in these checks; compatibility and correct playback timing still require checking real sample footage.

## Add this folder to GitHub

Suggested repository name: **dvr-video-tools**.

Suggested description: **Bash utilities for parallel DVR video remuxing, four-view camera cropping, and frame-rate troubleshooting with FFmpeg.**

Create an empty repository under your GitHub account. Choose its visibility deliberately. For a public portfolio, publish the source files and documentation without private recordings or client information. Leave GitHub's README, `.gitignore`, and license initialization options unchecked when using the commands below.

From this extracted folder:

```bash
git init -b main
git add README.md ConvertParallel.sh fix_dvr_framerate.sh .gitignore
git diff --cached --stat
git commit -m "Add DVR video scripts and detailed documentation"
git remote add origin https://github.com/pedroenvogue/dvr-video-tools.git
git push -u origin main
```

Authenticate using your normal GitHub Git setup. GitHub account passwords are not accepted as Git HTTPS passwords; use a supported credential manager, personal access token, or SSH setup. Never put a token in the README or commit it into the repository.

Alternatively, use GitHub's **uploading an existing file** option and upload these four files into the repository root. `.gitignore` can be hidden by a local file chooser; enable hidden-file display if needed.

For future updates:

```bash
git status
git add README.md ConvertParallel.sh fix_dvr_framerate.sh .gitignore
git diff --cached
git commit -m "Describe the change you made"
git push
```

No license has been selected for this package. Choose an appropriate license before presenting the project as open source.

## References

- [FFmpeg command-line documentation](https://ffmpeg.org/ffmpeg.html)
- [FFprobe documentation](https://ffmpeg.org/ffprobe.html)
- [FFmpeg crop filter](https://ffmpeg.org/ffmpeg-filters.html#crop)
- [GNU Parallel manual](https://www.gnu.org/software/parallel/man.html)
- [GitHub: creating a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)

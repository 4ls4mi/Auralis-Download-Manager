//! Read-only comparison of saved download ranges with BitTorrent v1 piece hashes.
//!
//! A match describes only the pieces compared; it does not establish the identity
//! of unseen bytes or authorize replacing the original partial download.

use crate::planner::SavedSegment;
use sha1::{Digest, Sha1};
use std::io::{self, Read, Seek, SeekFrom};

#[derive(Debug, PartialEq, Eq)]
pub struct PieceComparison {
    pub matching: Vec<usize>,
    pub mismatching: Vec<usize>,
    pub unavailable: Vec<usize>,
}

/// Compare only pieces entirely covered by committed ranges. Offsets and hashes
/// describe a single-file v1 torrent. This function never modifies the input.
pub fn compare_v1_pieces<R: Read + Seek>(
    file: &mut R,
    size: u64,
    segments: &[SavedSegment],
    piece_length: u64,
    hashes: &[[u8; 20]],
) -> io::Result<PieceComparison> {
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid download ranges or torrent pieces",
        )
    };
    if piece_length == 0 || size == 0 || size.div_ceil(piece_length) != hashes.len() as u64 {
        return Err(invalid());
    }
    let mut expected = 0;
    for s in segments {
        if s.start != expected
            || s.end <= s.start
            || s.cursor < s.start
            || s.cursor > s.end
            || s.end > size
        {
            return Err(invalid());
        }
        expected = s.end;
    }
    if expected != size {
        return Err(invalid());
    }
    let mut result = PieceComparison {
        matching: Vec::new(),
        mismatching: Vec::new(),
        unavailable: Vec::new(),
    };
    let mut buffer = [0u8; 64 * 1024];
    for (index, hash) in hashes.iter().enumerate() {
        let start = (index as u64)
            .checked_mul(piece_length)
            .ok_or_else(invalid)?;
        let end = start.saturating_add(piece_length).min(size);
        let mut covered = start;
        for s in segments {
            if s.cursor <= covered {
                continue;
            }
            if s.start > covered {
                break;
            }
            covered = covered.max(s.cursor).min(end);
            if covered == end {
                break;
            }
        }
        if covered != end {
            result.unavailable.push(index);
            continue;
        }
        file.seek(SeekFrom::Start(start))?;
        let mut remaining = end - start;
        let mut digest = Sha1::new();
        while remaining > 0 {
            let take = remaining.min(buffer.len() as u64) as usize;
            file.read_exact(&mut buffer[..take])?;
            digest.update(&buffer[..take]);
            remaining -= take as u64;
        }
        if digest.finalize().as_slice() == hash {
            result.matching.push(index);
        } else {
            result.mismatching.push(index);
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    fn hash(bytes: &[u8]) -> [u8; 20] {
        Sha1::digest(bytes).into()
    }
    #[test]
    fn compares_only_complete_saved_pieces_across_segments() {
        let segments = [
            SavedSegment {
                start: 0,
                cursor: 3,
                end: 3,
            },
            SavedSegment {
                start: 3,
                cursor: 6,
                end: 8,
            },
            SavedSegment {
                start: 8,
                cursor: 10,
                end: 10,
            },
        ];
        let result = compare_v1_pieces(
            &mut Cursor::new(b"abcdefghij"),
            10,
            &segments,
            4,
            &[hash(b"abcd"), hash(b"efgh"), hash(b"ij")],
        )
        .unwrap();
        assert_eq!(
            result,
            PieceComparison {
                matching: vec![0, 2],
                mismatching: vec![],
                unavailable: vec![1]
            }
        );
    }
    #[test]
    fn detects_different_piece_and_rejects_invalid_layout() {
        let segments = [SavedSegment {
            start: 0,
            cursor: 4,
            end: 4,
        }];
        let mut file = Cursor::new(b"abcd");
        let result = compare_v1_pieces(&mut file, 4, &segments, 4, &[hash(b"wxyz")]).unwrap();
        assert_eq!(result.mismatching, vec![0]);
        assert!(compare_v1_pieces(&mut file, 4, &segments, 0, &[]).is_err());
        assert!(
            compare_v1_pieces(&mut file, 5, &segments, 4, &[hash(b"abcd"), hash(b"e")]).is_err()
        );
    }
}

/// A hash of bytes known to have been saved, not a publisher-provided checksum.
#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct SavedBlockHash {
    pub start: u64,
    pub end: u64,
    pub sha256: [u8; 32],
}

/// Hash a committed byte range. The caller must only record ranges after flushing
/// their data, and must persist their range map and hashes atomically together.
pub fn hash_saved_block<R: Read + Seek>(
    file: &mut R,
    start: u64,
    end: u64,
) -> io::Result<SavedBlockHash> {
    use sha2::Sha256;
    if start >= end {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "empty or inverted block",
        ));
    }
    file.seek(SeekFrom::Start(start))?;
    let mut digest = Sha256::new();
    let mut remaining = end - start;
    let mut buffer = [0u8; 64 * 1024];
    while remaining > 0 {
        let take = remaining.min(buffer.len() as u64) as usize;
        file.read_exact(&mut buffer[..take])?;
        digest.update(&buffer[..take]);
        remaining -= take as u64;
    }
    Ok(SavedBlockHash {
        start,
        end,
        sha256: digest.finalize().into(),
    })
}

/// Check previously recorded blocks without changing the file or claiming that
/// bytes that were never hashed are valid. Short files are reported as errors.
pub fn check_saved_blocks<R: Read + Seek>(
    file: &mut R,
    blocks: &[SavedBlockHash],
    size: u64,
) -> io::Result<Vec<usize>> {
    let mut damaged = Vec::new();
    let mut previous_end = 0;
    for (index, block) in blocks.iter().enumerate() {
        if block.start < previous_end || block.start >= block.end || block.end > size {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid block hash ranges",
            ));
        }
        if hash_saved_block(file, block.start, block.end)?.sha256 != block.sha256 {
            damaged.push(index);
        }
        previous_end = block.end;
    }
    Ok(damaged)
}

#[cfg(test)]
mod block_tests {
    use super::*;
    use std::io::Cursor;
    #[test]
    fn detects_corruption_only_in_recorded_blocks_including_partial_blocks() {
        let mut original = Cursor::new(b"abcdefghij".to_vec());
        let blocks = vec![
            hash_saved_block(&mut original, 0, 4).unwrap(),
            hash_saved_block(&mut original, 8, 10).unwrap(),
        ];
        let mut intact = Cursor::new(b"abcdXXghij".to_vec());
        assert!(
            check_saved_blocks(&mut intact, &blocks, 10)
                .unwrap()
                .is_empty()
        );
        let mut damaged = Cursor::new(b"abXdXXghiY".to_vec());
        assert_eq!(
            check_saved_blocks(&mut damaged, &blocks, 10).unwrap(),
            vec![0, 1]
        );
    }
    #[test]
    fn rejects_overlaps_invalid_ranges_and_short_files() {
        let mut file = Cursor::new(b"abcdefgh".to_vec());
        assert!(hash_saved_block(&mut file, 2, 2).is_err());
        let first = hash_saved_block(&mut file, 0, 4).unwrap();
        let second = hash_saved_block(&mut file, 3, 6).unwrap();
        assert!(check_saved_blocks(&mut file, &[first.clone(), second], 8).is_err());
        assert!(check_saved_blocks(&mut Cursor::new(b"a".to_vec()), &[first], 8).is_err());
    }
}

/// Maximum size of an individual hash record at a durable checkpoint.
pub const CHECKPOINT_BLOCK_SIZE: u64 = 4 * 1024 * 1024;

/// Hash each newly saved range, including partial blocks, without replacing old
/// hashes. Every record lies wholly inside committed data and is at most one block.
pub fn capture_checkpoint_blocks<R: Read + Seek>(
    file: &mut R,
    size: u64,
    segments: &[SavedSegment],
    existing: &[SavedBlockHash],
    block_size: u64,
) -> io::Result<Vec<SavedBlockHash>> {
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid checkpoint ranges or block hashes",
        )
    };
    if block_size == 0 || crate::planner::Planner::resume(size, 1, segments).is_err() {
        return Err(invalid());
    }
    let mut ranges: Vec<(u64, u64)> = Vec::new();
    for s in segments {
        if s.start == s.cursor {
            continue;
        }
        if let Some(last) = ranges.last_mut() {
            if last.1 == s.start {
                last.1 = s.cursor;
                continue;
            }
        }
        ranges.push((s.start, s.cursor));
    }
    let mut previous_end = 0;
    for block in existing {
        if block.start < previous_end
            || block.start >= block.end
            || block.end > size
            || block.end - block.start > block_size
            || !ranges
                .iter()
                .any(|&(a, b)| a <= block.start && block.end <= b)
        {
            return Err(invalid());
        }
        previous_end = block.end;
    }
    let mut result = existing.to_vec();
    for (start, end) in ranges {
        let mut at = start;
        for block in existing
            .iter()
            .filter(|block| block.start >= start && block.start < end)
        {
            while at < block.start {
                let stop = at.saturating_add(block_size).min(block.start);
                result.push(hash_saved_block(file, at, stop)?);
                at = stop;
            }
            at = block.end;
        }
        while at < end {
            let stop = at.saturating_add(block_size).min(end);
            result.push(hash_saved_block(file, at, stop)?);
            at = stop;
        }
    }
    result.sort_unstable_by_key(|block| block.start);
    Ok(result)
}

#[cfg(test)]
mod checkpoint_tests {
    use super::*;
    use std::io::Cursor;
    #[test]
    fn checkpoints_only_committed_blocks_and_preserves_old_hashes() {
        let mut file = Cursor::new(b"abcdefghijkl".to_vec());
        let partial = [
            SavedSegment {
                start: 0,
                cursor: 2,
                end: 2,
            },
            SavedSegment {
                start: 2,
                cursor: 5,
                end: 8,
            },
            SavedSegment {
                start: 8,
                cursor: 10,
                end: 12,
            },
        ];
        let first = capture_checkpoint_blocks(&mut file, 12, &partial, &[], 4).unwrap();
        assert_eq!(
            first.iter().map(|b| (b.start, b.end)).collect::<Vec<_>>(),
            vec![(0, 4), (4, 5), (8, 10)]
        );
        file.get_mut()[0] = b'X';
        let complete = [SavedSegment {
            start: 0,
            cursor: 12,
            end: 12,
        }];
        let next = capture_checkpoint_blocks(&mut file, 12, &complete, &first, 4).unwrap();
        assert_eq!(next.len(), 5);
        assert_eq!(next[0], first[0]);
        assert_eq!(check_saved_blocks(&mut file, &next, 12).unwrap(), vec![0]);
    }
    #[test]
    fn rejects_hashes_outside_committed_ranges() {
        let mut file = Cursor::new(b"abcdefgh".to_vec());
        let stale = hash_saved_block(&mut file, 4, 8).unwrap();
        let segments = [SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        assert!(capture_checkpoint_blocks(&mut file, 8, &segments, &[stale], 4).is_err());
    }
}

/// Result of comparing the saved file to locally recorded hashes. These hashes
/// detect later changes; they do not authenticate what the server originally sent.
#[derive(Debug, PartialEq, Eq)]
pub struct CheckpointVerification {
    pub checked_bytes: u64,
    pub unhashed_bytes: u64,
    pub damaged_ranges: Vec<(u64, u64)>,
}

/// Compare saved bytes with their checkpoint hashes, reporting older downloads'
/// unhashed bytes separately. This function does not change the file or state.
pub fn verify_checkpoint<R: Read + Seek>(
    file: &mut R,
    size: u64,
    segments: &[SavedSegment],
    blocks: &[SavedBlockHash],
) -> io::Result<CheckpointVerification> {
    if crate::planner::Planner::resume(size, 1, segments).is_err() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid saved segment map",
        ));
    }
    let mut ranges: Vec<(u64, u64)> = Vec::new();
    for segment in segments {
        if segment.cursor == segment.start {
            continue;
        }
        if let Some(last) = ranges.last_mut() {
            if last.1 == segment.start {
                last.1 = segment.cursor;
                continue;
            }
        }
        ranges.push((segment.start, segment.cursor));
    }
    let saved_bytes: u64 = ranges.iter().map(|(a, b)| b - a).sum();
    let mut previous_end = 0;
    let mut checked_bytes = 0u64;
    let mut damaged_ranges = Vec::new();
    for block in blocks {
        if block.start < previous_end
            || block.start >= block.end
            || block.end > size
            || !ranges
                .iter()
                .any(|&(a, b)| a <= block.start && block.end <= b)
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid checkpoint hash range",
            ));
        }
        if hash_saved_block(file, block.start, block.end)?.sha256 != block.sha256 {
            damaged_ranges.push((block.start, block.end));
        }
        checked_bytes += block.end - block.start;
        previous_end = block.end;
    }
    Ok(CheckpointVerification {
        checked_bytes,
        unhashed_bytes: saved_bytes - checked_bytes,
        damaged_ranges,
    })
}

#[cfg(test)]
mod verify_checkpoint_tests {
    use super::*;
    use std::io::Cursor;
    #[test]
    fn distinguishes_unhashed_and_damaged_bytes() {
        let segments = [SavedSegment {
            start: 0,
            cursor: 6,
            end: 8,
        }];
        let mut original = Cursor::new(b"abcdefgh".to_vec());
        let hash = hash_saved_block(&mut original, 0, 4).unwrap();
        let mut damaged = Cursor::new(b"abXdefgh".to_vec());
        assert_eq!(
            verify_checkpoint(&mut damaged, 8, &segments, &[hash]).unwrap(),
            CheckpointVerification {
                checked_bytes: 4,
                unhashed_bytes: 2,
                damaged_ranges: vec![(0, 4)]
            }
        );
        assert_eq!(
            verify_checkpoint(&mut original, 8, &segments, &[])
                .unwrap()
                .unhashed_bytes,
            6
        );
    }
    #[test]
    fn refuses_hashes_for_bytes_that_were_never_downloaded() {
        let segments = [SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        let mut file = Cursor::new(b"abcdefgh".to_vec());
        let hole = hash_saved_block(&mut file, 4, 8).unwrap();
        assert!(verify_checkpoint(&mut file, 8, &segments, &[hole]).is_err());
    }
}

/// Build a proposed range map that re-fetches damaged ranges while keeping all
/// other saved ranges. This only constructs a plan: it never writes state or data.
/// The caller must confirm that a compatible range source exists before applying it.
pub fn plan_range_repair(
    size: u64,
    segments: &[SavedSegment],
    damaged: &[(u64, u64)],
) -> io::Result<Vec<SavedSegment>> {
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid saved or damaged ranges",
        )
    };
    if crate::planner::Planner::resume(size, 1, segments).is_err() {
        return Err(invalid());
    }
    let mut saved_ranges: Vec<(u64, u64)> = Vec::new();
    for s in segments {
        if s.start == s.cursor {
            continue;
        }
        if let Some(last) = saved_ranges.last_mut() {
            if last.1 == s.start {
                last.1 = s.cursor;
                continue;
            }
        }
        saved_ranges.push((s.start, s.cursor));
    }
    let mut previous_end = 0;
    for &(start, end) in damaged {
        if start < previous_end
            || start >= end
            || end > size
            || !saved_ranges.iter().any(|&(a, b)| a <= start && end <= b)
        {
            return Err(invalid());
        }
        previous_end = end;
    }
    let mut boundaries = vec![0, size];
    for s in segments {
        boundaries.extend([s.start, s.cursor, s.end]);
    }
    for &(start, end) in damaged {
        boundaries.extend([start, end]);
    }
    boundaries.sort_unstable();
    boundaries.dedup();
    let mut plan: Vec<SavedSegment> = Vec::new();
    for pair in boundaries.windows(2) {
        let (start, end) = (pair[0], pair[1]);
        let present = saved_ranges.iter().any(|&(a, b)| a <= start && end <= b)
            && !damaged.iter().any(|&(a, b)| a < end && start < b);
        if let Some(last) = plan.last_mut() {
            let last_present = last.cursor == last.end;
            if last.end == start && last_present == present {
                last.end = end;
                if present {
                    last.cursor = end;
                }
                continue;
            }
        }
        plan.push(SavedSegment {
            start,
            cursor: if present { end } else { start },
            end,
        });
    }
    Ok(plan)
}

#[cfg(test)]
mod repair_plan_tests {
    use super::*;
    #[test]
    fn keeps_good_bytes_on_both_sides_of_damage_and_gaps() {
        let original = vec![
            SavedSegment {
                start: 0,
                cursor: 6,
                end: 8,
            },
            SavedSegment {
                start: 8,
                cursor: 12,
                end: 12,
            },
        ];
        let plan = plan_range_repair(12, &original, &[(2, 4), (9, 11)]).unwrap();
        assert_eq!(
            plan,
            vec![
                SavedSegment {
                    start: 0,
                    cursor: 2,
                    end: 2
                },
                SavedSegment {
                    start: 2,
                    cursor: 2,
                    end: 4
                },
                SavedSegment {
                    start: 4,
                    cursor: 6,
                    end: 6
                },
                SavedSegment {
                    start: 6,
                    cursor: 6,
                    end: 8
                },
                SavedSegment {
                    start: 8,
                    cursor: 9,
                    end: 9
                },
                SavedSegment {
                    start: 9,
                    cursor: 9,
                    end: 11
                },
                SavedSegment {
                    start: 11,
                    cursor: 12,
                    end: 12
                },
            ]
        );
        assert!(crate::planner::Planner::resume(12, 1, &plan).is_ok());
        assert_eq!(original[0].cursor, 6);
    }
    #[test]
    fn refuses_damage_in_an_unwritten_gap_or_overlaps() {
        let segments = [SavedSegment {
            start: 0,
            cursor: 4,
            end: 8,
        }];
        assert!(plan_range_repair(8, &segments, &[(3, 5)]).is_err());
        assert!(plan_range_repair(8, &segments, &[(0, 3), (2, 4)]).is_err());
    }
}

/// Copy only complete, matching torrent pieces into a new sparse file. The
/// original remains untouched; unverified fragments are deliberately omitted.
/// The caller must keep the source stopped and must independently obtain and
/// validate trustworthy torrent metadata. A match describes only copied bytes.
pub fn stage_matching_pieces(
    source: &std::path::Path,
    destination: &std::path::Path,
    size: u64,
    segments: &[SavedSegment],
    piece_length: u64,
    hashes: &[[u8; 20]],
) -> io::Result<PieceComparison> {
    let mut input = std::fs::File::open(source)?;
    if input.metadata()?.len() != size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "partial file has the wrong size",
        ));
    }
    let comparison = compare_v1_pieces(&mut input, size, segments, piece_length, hashes)?;
    stage_compared_pieces(
        &mut input,
        destination,
        size,
        0,
        size,
        piece_length,
        hashes,
        comparison,
    )
}

/// Stage only complete pieces that lie entirely inside one file of a torrent.
/// Pieces spanning neighboring files remain unavailable and are not copied.
pub fn stage_matching_file_pieces(
    source: &std::path::Path,
    destination: &std::path::Path,
    file_size: u64,
    segments: &[SavedSegment],
    torrent_size: u64,
    file_offset: u64,
    piece_length: u64,
    hashes: &[[u8; 20]],
) -> io::Result<PieceComparison> {
    let mut input = std::fs::File::open(source)?;
    if input.metadata()?.len() != file_size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "partial file has the wrong size",
        ));
    }
    let comparison = compare_v1_file_pieces(
        &mut input,
        file_size,
        segments,
        torrent_size,
        file_offset,
        piece_length,
        hashes,
    )?;
    stage_compared_pieces(
        &mut input,
        destination,
        file_size,
        file_offset,
        torrent_size,
        piece_length,
        hashes,
        comparison,
    )
}

fn stage_compared_pieces(
    source: &mut std::fs::File,
    destination: &std::path::Path,
    file_size: u64,
    file_offset: u64,
    torrent_size: u64,
    piece_length: u64,
    hashes: &[[u8; 20]],
    comparison: PieceComparison,
) -> io::Result<PieceComparison> {
    use std::io::Write;
    let invalid = || io::Error::new(io::ErrorKind::InvalidData, "invalid matching piece range");
    if comparison.matching.is_empty() || !comparison.mismatching.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "saved bytes do not establish a matching torrent piece",
        ));
    }
    let local_range = |index: usize| -> io::Result<(u64, u64)> {
        let start = (index as u64)
            .checked_mul(piece_length)
            .ok_or_else(invalid)?;
        let end = start.saturating_add(piece_length).min(torrent_size);
        let local = start.checked_sub(file_offset).ok_or_else(invalid)?;
        let local_end = end.checked_sub(file_offset).ok_or_else(invalid)?;
        if local >= local_end || local_end > file_size || index >= hashes.len() {
            return Err(invalid());
        }
        Ok((local, local_end))
    };
    let mut output = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(destination)?;
    let result = (|| -> io::Result<()> {
        crate::sparse::set(&output, true);
        output.set_len(file_size)?;
        let mut buffer = [0u8; 64 * 1024];
        for &index in &comparison.matching {
            let (start, end) = local_range(index)?;
            source.seek(SeekFrom::Start(start))?;
            output.seek(SeekFrom::Start(start))?;
            let mut left = end - start;
            while left > 0 {
                let n = left.min(buffer.len() as u64) as usize;
                source.read_exact(&mut buffer[..n])?;
                output.write_all(&buffer[..n])?;
                left -= n as u64;
            }
        }
        output.sync_all()?;
        for &index in &comparison.matching {
            let (start, end) = local_range(index)?;
            let mut left = end - start;
            let mut digest = Sha1::new();
            output.seek(SeekFrom::Start(start))?;
            while left > 0 {
                let n = left.min(buffer.len() as u64) as usize;
                output.read_exact(&mut buffer[..n])?;
                digest.update(&buffer[..n]);
                left -= n as u64;
            }
            if digest.finalize().as_slice() != hashes[index] {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "a copied torrent piece changed",
                ));
            }
        }
        Ok(())
    })();
    drop(output);
    if let Err(error) = result {
        let _ = std::fs::remove_file(destination);
        return Err(error);
    }
    Ok(comparison)
}

#[cfg(test)]
mod stage_piece_tests {
    use super::*;
    #[test]
    fn stages_only_verified_pieces_and_never_overwrites_existing_data() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("partial");
        std::fs::write(&source, b"abcdefghijkl").unwrap();
        let hashes: Vec<[u8; 20]> = [b"abcd", b"efgh", b"ijkl"]
            .into_iter()
            .map(|b| Sha1::digest(b).into())
            .collect();
        let segments = [
            SavedSegment {
                start: 0,
                cursor: 6,
                end: 8,
            },
            SavedSegment {
                start: 8,
                cursor: 12,
                end: 12,
            },
        ];
        let output = dir.path().join("torrent-file");
        let report = stage_matching_pieces(&source, &output, 12, &segments, 4, &hashes).unwrap();
        assert_eq!(report.matching, vec![0, 2]);
        assert_eq!(std::fs::read(&output).unwrap(), b"abcd\0\0\0\0ijkl");
        assert_eq!(std::fs::read(&source).unwrap(), b"abcdefghijkl");
        assert!(stage_matching_pieces(&source, &output, 12, &segments, 4, &hashes).is_err());
        assert_eq!(std::fs::read(&output).unwrap(), b"abcd\0\0\0\0ijkl");
        let bad = dir.path().join("bad");
        let mut wrong = hashes.clone();
        wrong[0] = Sha1::digest(b"xxxx").into();
        assert!(stage_matching_pieces(&source, &bad, 12, &segments, 4, &wrong).is_err());
        assert!(!bad.exists());
        let incomplete = [SavedSegment {
            start: 0,
            cursor: 2,
            end: 12,
        }];
        let no_complete_piece = dir.path().join("no-complete-piece");
        assert!(
            stage_matching_pieces(&source, &no_complete_piece, 12, &incomplete, 4, &hashes)
                .is_err()
        );
        assert!(!no_complete_piece.exists());
    }
}

/// Compare a single saved file against pieces in a multi-file v1 torrent.
/// Boundary pieces touching another file are unavailable, even when the saved
/// file contains its own bytes for that piece; they require the neighboring file.
pub fn compare_v1_file_pieces<R: Read + Seek>(
    file: &mut R,
    file_size: u64,
    segments: &[SavedSegment],
    torrent_size: u64,
    file_offset: u64,
    piece_length: u64,
    hashes: &[[u8; 20]],
) -> io::Result<PieceComparison> {
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid torrent file or saved ranges",
        )
    };
    let file_end = file_offset.checked_add(file_size).ok_or_else(invalid)?;
    if file_size == 0
        || piece_length == 0
        || file_end > torrent_size
        || torrent_size.div_ceil(piece_length) != hashes.len() as u64
        || crate::planner::Planner::resume(file_size, 1, segments).is_err()
    {
        return Err(invalid());
    }
    let mut result = PieceComparison {
        matching: Vec::new(),
        mismatching: Vec::new(),
        unavailable: Vec::new(),
    };
    let mut buffer = [0u8; 64 * 1024];
    for (index, hash) in hashes.iter().enumerate() {
        let start = (index as u64)
            .checked_mul(piece_length)
            .ok_or_else(invalid)?;
        let end = start.saturating_add(piece_length).min(torrent_size);
        if start < file_offset || end > file_end {
            result.unavailable.push(index);
            continue;
        }
        let local_start = start - file_offset;
        let local_end = end - file_offset;
        let mut covered = local_start;
        for segment in segments {
            if segment.cursor <= covered {
                continue;
            }
            if segment.start > covered {
                break;
            }
            covered = covered.max(segment.cursor).min(local_end);
            if covered == local_end {
                break;
            }
        }
        if covered != local_end {
            result.unavailable.push(index);
            continue;
        }
        file.seek(SeekFrom::Start(local_start))?;
        let mut remaining = local_end - local_start;
        let mut digest = Sha1::new();
        while remaining > 0 {
            let n = remaining.min(buffer.len() as u64) as usize;
            file.read_exact(&mut buffer[..n])?;
            digest.update(&buffer[..n]);
            remaining -= n as u64;
        }
        if digest.finalize().as_slice() == hash {
            result.matching.push(index);
        } else {
            result.mismatching.push(index);
        }
    }
    Ok(result)
}

#[cfg(test)]
mod multi_file_piece_tests {
    use super::*;
    use std::io::Cursor;
    #[test]
    fn only_compares_pieces_wholly_contained_in_the_saved_file() {
        let all = b"abcdefghijkl";
        let hashes: Vec<[u8; 20]> = all
            .chunks(4)
            .map(|piece| Sha1::digest(piece).into())
            .collect();
        let segments = [SavedSegment {
            start: 0,
            cursor: 8,
            end: 8,
        }];
        let result = compare_v1_file_pieces(
            &mut Cursor::new(b"cdefghij"),
            8,
            &segments,
            12,
            2,
            4,
            &hashes,
        )
        .unwrap();
        assert_eq!(result.matching, vec![1]);
        assert_eq!(result.unavailable, vec![0, 2]);
        assert!(result.mismatching.is_empty());
        let changed = compare_v1_file_pieces(
            &mut Cursor::new(b"cdXXghij"),
            8,
            &segments,
            12,
            2,
            4,
            &hashes,
        )
        .unwrap();
        assert_eq!(changed.mismatching, vec![1]);
        assert!(
            compare_v1_file_pieces(
                &mut Cursor::new(b"cdefghij"),
                8,
                &segments,
                12,
                5,
                4,
                &hashes
            )
            .is_err()
        );
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("partial");
        let output = dir.path().join("target");
        std::fs::write(&source, b"cdefghij").unwrap();
        let staged = stage_matching_file_pieces(&source, &output, 8, &segments, 12, 2, 4, &hashes).unwrap();
        assert_eq!(staged.matching, vec![1]);
        assert_eq!(std::fs::read(output).unwrap(), b"\0\0efgh\0\0");
        assert_eq!(std::fs::read(source).unwrap(), b"cdefghij");
    }
}

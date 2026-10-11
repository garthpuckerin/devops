#!/bin/sh
# GCPMedia scheduled config backup (v2, 2026-10-11)
# Backs up compose files, app configs and CONSISTENT database copies to a dated archive.
#   - Postgres: every running postgres/pgvector container, every database + roles,
#     pg_dump -Fc verified with pg_restore --list (named volumes live outside
#     /volume1/docker, so a dump is the ONLY copy the archive gets of them).
#   - SQLite: every live SQLite file under /volume1/docker gets a .backup snapshot
#     (one read transaction: consistent even while the app writes); the live file
#     and its -wal/-shm are then left out of the tar. A failed snapshot keeps the
#     live file in the tar as a fallback.
# Excludes heavy re-creatable data (media metadata, caches, ollama models) and
# copies of copies (DB backups/snapshots, test/qualification copies, deploy tarballs).
# Not backed up on purpose: mimir2 Neo4j/Redis (rebuilt from git by re-ingest).
# Retention: keeps the newest $KEEP archives, prunes older ones.
# Usage: gcpmedia-config-backup.sh [--stage-test]
#   --stage-test  run the dumps and snapshots, verify them, report, clean up; no archive.
set -u

DOCKER=/volume1/@appstore/ContainerManager/usr/bin/docker
SRC=/volume1/docker
DEST=/volume1/docker/_codex_backups/scheduled
KEEP=14
TS=$(date +%Y%m%d-%H%M%S)
ARCHIVE=$DEST/gcpmedia-config-backup-$TS.tgz
LOG=$DEST/backup.log
MODE=${1:-full}
NICE="nice -n 19"

mkdir -p "$DEST"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

STAGE="$SRC/_codex_backups/.staging-$TS"
mkdir -p "$STAGE/db-dumps" "$STAGE/sqlite"
EXCLUDES="$STAGE/excludes.txt"
: > "$EXCLUDES"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

log "START $MODE $ARCHIVE"
BACKUP_ERRORS=0

# --- Postgres: discover, dump every database + roles ---------------------------
# dump_pg <container> <user> <database> ; 0 only on a dump pg_restore can read.
dump_pg() {
    out="$STAGE/db-dumps/$1--$3.dump"
    if $DOCKER exec "$1" pg_dump -U "$2" -Fc "$3" > "$out" 2>> "$LOG" \
        && [ "$(wc -c < "$out")" -ge 512 ] \
        && $DOCKER exec -i "$1" pg_restore --list < "$out" > /dev/null 2>> "$LOG"; then
        log "pg_dump $1/$3 OK ($(du -h "$out" | cut -f1))"
        return 0
    fi
    log "ERROR pg_dump $1/$3 failed or unreadable"
    rm -f "$out"; return 1
}

for c in $($DOCKER ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /postgres|pgvector|postgis/ {print $1}'); do
    user=$($DOCKER inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^POSTGRES_USER=//p')
    user=${user:-postgres}
    c_errors=0
    if $DOCKER exec "$c" pg_dumpall -U "$user" --globals-only > "$STAGE/db-dumps/$c--globals.sql" 2>> "$LOG"; then
        log "pg_dumpall globals $c OK"
    else
        log "ERROR pg_dumpall globals $c"; c_errors=$((c_errors + 1))
    fi
    dbs=$($DOCKER exec "$c" psql -U "$user" -d postgres -tAc "SELECT datname FROM pg_database WHERE NOT datistemplate" 2>> "$LOG")
    if [ -z "$dbs" ]; then
        log "ERROR $c: could not list databases"; c_errors=$((c_errors + 1))
    fi
    for db in $dbs; do
        dump_pg "$c" "$user" "$db" || c_errors=$((c_errors + 1))
    done
    BACKUP_ERRORS=$((BACKUP_ERRORS + c_errors))
    # A bind-mounted data dir under /volume1/docker is a live, mid-write copy:
    # leave it out of the tar once every database of that container dumped cleanly.
    if [ "$c_errors" -eq 0 ]; then
        $DOCKER inspect "$c" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}' \
            | sed -n "s#^/volume1/docker/#docker/#p" >> "$EXCLUDES"
    fi
done

# --- SQLite: consistent snapshot of every live database under /volume1/docker ----
# Prune the same trees the tar leaves out, plus copies of copies.
SQLITE_LIST="$STAGE/sqlite-files.txt"
$NICE find "$SRC" \
    \( -path "$SRC/_codex_backups" -o -path "$SRC/_quarantine" -o -path "$SRC/_archive" \
       -o -path "$SRC/_scripts" -o -name '#recycle' -o -name '@eaDir' -o -name node_modules -o -name .git \
       -o -path "$SRC/ollama" -o -path "$SRC/mediaos/qualification-*" -o -path "$SRC/mediaos/pilot-*" \
       -o -path "$SRC/shadowstream/data/archive" -o -path "$SRC/jellyfin/data/metadata" -o -path "$SRC/jellyfin/cache" \
       -o -path "$SRC/plex/Library/Application Support/Plex Media Server/Cache" \
       -o -path "$SRC/plex/Library/Application Support/Plex Media Server/Metadata" \
       -o -path "$SRC/plex/Library/Application Support/Plex Media Server/Media" \) -prune \
    -o -type f -size +0 \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) \
       ! -name 'backup-*' ! -name 'snapshot-*' ! -name 'drycopy-*' -print 2>/dev/null > "$SQLITE_LIST"

SQLITE_OK=0
while IFS= read -r f; do
    [ "$(head -c 15 "$f" 2>/dev/null | tr -d '\000')" = "SQLite format 3" ] || continue
    rel=${f#/volume1/}
    dst="$STAGE/sqlite/$rel"
    mkdir -p "$(dirname "$dst")"
    # -readonly: never create or checkpoint the app's -wal/-shm (a root-owned
    # -shm would lock a non-root app out of its own database); a database the
    # read-only connection cannot open falls back to the live copy below.
    if timeout 900 $NICE sqlite3 -readonly "$f" ".timeout 20000" ".backup \"$dst\"" 2>> "$LOG"; then
        pc=$(sqlite3 "$dst" "PRAGMA page_count;" 2>/dev/null); ps=$(sqlite3 "$dst" "PRAGMA page_size;" 2>/dev/null)
        if [ -n "$pc" ] && [ -n "$ps" ] && [ "$((pc * ps))" -eq "$(stat -c %s "$dst")" ] && [ "$pc" -gt 0 ]; then
            printf '%s\n%s-wal\n%s-shm\n%s-journal\n' "$rel" "$rel" "$rel" "$rel" >> "$EXCLUDES"
            SQLITE_OK=$((SQLITE_OK + 1))
            continue
        fi
    fi
    log "ERROR sqlite snapshot $f failed; live file kept in archive"
    rm -f "$dst"; BACKUP_ERRORS=$((BACKUP_ERRORS + 1))
done < "$SQLITE_LIST"
log "sqlite snapshots OK: $SQLITE_OK ($(du -sh "$STAGE/sqlite" | cut -f1))"
cat > "$STAGE/sqlite/README.txt" <<'EOF'
Consistent SQLite snapshots (sqlite3 .backup) of the live databases. The archive's
docker/ tree omits these live files (and their -wal/-shm). To restore one, stop its
container and copy sqlite/docker/<path> over docker/<path>, deleting any -wal/-shm.
EOF

if [ "$MODE" = "--stage-test" ]; then
    log "STAGE-TEST done: $(ls "$STAGE/db-dumps" | wc -l) pg files, $SQLITE_OK sqlite snapshots, $(wc -l < "$EXCLUDES") exclude lines, errors=$BACKUP_ERRORS"
    echo "pg files:"; ls -la "$STAGE/db-dumps" | awk 'NR>1 {print "  " $5, $9}'
    echo "sqlite snapshots: $SQLITE_OK ($(du -sh "$STAGE/sqlite" | cut -f1))"
    echo "exclude lines: $(wc -l < "$EXCLUDES")"; echo "errors: $BACKUP_ERRORS"
    tail -n 40 "$LOG" | grep -E 'ERROR' | sed 's/^/  /'
    exit 0
fi

# --- Config archive ---
# Global excludes match any path component.
$NICE tar czf "$ARCHIVE" \
    --exclude-from="$EXCLUDES" \
    --exclude='@eaDir' \
    --exclude='#recycle' \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='MediaCover' \
    --exclude='docker/_codex_backups' \
    --exclude='docker/_quarantine' \
    --exclude='docker/_scripts' \
    --exclude='docker/_archive' \
    --exclude='docker/ollama' \
    --exclude='docker/mimir-stack/images' \
    --exclude='docker/mediaos/qualification-*' \
    --exclude='docker/mediaos/pilot-*' \
    --exclude='docker/shadowstream/data/archive' \
    --exclude='docker/shadowstream/data/backup-*' \
    --exclude='docker/shadowstream/data/snapshot-*' \
    --exclude='docker/shadowstream/data/drycopy-*' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Cache' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Metadata' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Media' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Codecs' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Crash Reports' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Logs' \
    --exclude='docker/plex/Library/Application Support/Plex Media Server/Drivers' \
    --exclude='docker/jellyfin/cache' \
    --exclude='docker/jellyfin/transcode' \
    --exclude='docker/jellyfin/codecs' \
    --exclude='docker/jellyfin/log' \
    --exclude='docker/jellyfin/data/metadata' \
    --exclude='docker/jellyfin/metadata' \
    --exclude='docker/emby/cache' \
    --exclude='docker/emby/metadata' \
    --exclude='docker/emby/transcoding-temp' \
    --exclude='docker/emby/logs' \
    --exclude='docker/tautulli/cache' \
    --exclude='docker/open-webui/cache' \
    -C /volume1 docker \
    -C "$STAGE" db-dumps sqlite \
    2>> "$LOG"
TAR_RC=$?
# GNU tar rc=1 means "file changed while reading" - acceptable for live configs
# (databases are no longer read live; they come from the staged copies).
if [ "$TAR_RC" -gt 1 ]; then
    log "ERROR tar failed rc=$TAR_RC"
    rm -f "$ARCHIVE"
    exit 1
fi

# tar -tzf verifies both gzip integrity and tar structure (gzip -t checked compression only)
if $NICE tar -tzf "$ARCHIVE" > /dev/null 2>> "$LOG"; then
    log "ARCHIVE OK $(du -h "$ARCHIVE" | cut -f1) (tar rc=$TAR_RC)"
else
    log "ERROR archive failed integrity check"
    exit 1
fi

# --- Retention (whitespace-safe iteration) ---
COUNT=0
ls -1t "$DEST"/gcpmedia-config-backup-*.tgz 2>/dev/null | while IFS= read -r f; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -gt "$KEEP" ]; then
        rm -f "$f" && log "PRUNED $f"
    fi
done

if [ "$BACKUP_ERRORS" -gt 0 ]; then
    log "DONE WITH ERRORS ($BACKUP_ERRORS db failures) archives kept: $(ls -1 "$DEST"/gcpmedia-config-backup-*.tgz | wc -l)"
    exit 1
fi
log "DONE archives kept: $(ls -1 "$DEST"/gcpmedia-config-backup-*.tgz | wc -l)"
exit 0

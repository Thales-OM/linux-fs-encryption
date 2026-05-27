#define FUSE_USE_VERSION 31
#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sodium.h>
#include <limits.h>

#define NONCE_BYTES crypto_secretbox_NONCEBYTES
#define KEY_BYTES   crypto_secretbox_KEYBYTES

// 🔑 Ключ(32 байта). В production использовать keyring/vault.
static const unsigned char KEY[KEY_BYTES] = {
    0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
    0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
    0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f
};

static char backend[PATH_MAX];

static void get_raw_path(const char *path, char *out) {
    snprintf(out, PATH_MAX, "%s%s", backend, path);
}

static int encfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
    char raw[PATH_MAX];
    get_raw_path(path, raw);
    int res = lstat(raw, stbuf);
    if (res == -1) return -errno;

    if (S_ISREG(stbuf->st_mode)) {
        // Файл содержит: [NONCE (24B)][CIPHERTEXT]
        if (stbuf->st_size >= NONCE_BYTES)
            stbuf->st_size -= NONCE_BYTES;
        else
            stbuf->st_size = 0;
    }
    return 0;
}

static int encfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                         off_t offset, struct fuse_file_info *fi, enum fuse_readdir_flags flags) {
    char raw[PATH_MAX];
    get_raw_path(path, raw);
    DIR *dp = opendir(raw);
    if (!dp) return -errno;

    struct dirent *de;
    filler(buf, ".", NULL, 0, 0);
    filler(buf, "..", NULL, 0, 0);
    while ((de = readdir(dp)) != NULL) {
        struct stat st = {0};
        if (lstat(raw, &st) == 0)
            filler(buf, de->d_name, &st, 0, 0);
    }
    closedir(dp);
    return 0;
}

static int encfs_open(const char *path, struct fuse_file_info *fi) {
    char raw[PATH_MAX];
    get_raw_path(path, raw);
    int fd = open(raw, fi->flags);
    if (fd == -1) return -errno;
    fi->fh = fd;
    return 0;
}

static int encfs_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    struct stat st;
    fstat(fi->fh, &st);
    if (st.st_size < NONCE_BYTES) return -EIO;

    unsigned char *raw = malloc(st.st_size);
    if (!raw) return -ENOMEM;
    pread(fi->fh, raw, st.st_size, 0);

    // Разбираем: первые 24B = nonce, остальное = ciphertext
    unsigned char nonce[NONCE_BYTES];
    memcpy(nonce, raw, NONCE_BYTES);
    unsigned long long mlen = st.st_size - NONCE_BYTES;

    unsigned char *plain = malloc(mlen);
    if (!plain) { free(raw); return -ENOMEM; }

    if (crypto_secretbox_open_easy(plain, raw + NONCE_BYTES, mlen, nonce, KEY) != 0) {
        free(raw); free(plain); return -EIO;
    }

    // Копируем нужный диапазон (offset/size)
    size_t avail = mlen > offset ? mlen - offset : 0;
    size_t copy = avail < size ? avail : size;
    memcpy(buf, plain + offset, copy);

    free(raw); free(plain);
    return copy;
}

static int encfs_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    // 🎓 АКАДЕМИЧЕСКОЕ УПРОЩЕНИЕ: перезаписываем файл целиком.
    // Для production нужен блочный режим (CTR/GCM) с seek.
    
    struct stat st;
    fstat(fi->fh, &st);
    unsigned long long old_plain_len = (st.st_size > NONCE_BYTES) ? st.st_size - NONCE_BYTES : 0;
    unsigned char *old_plain = calloc(old_plain_len ? old_plain_len : 1, 1);
    
    if (old_plain_len > 0) {
        unsigned char *raw = malloc(st.st_size);
        pread(fi->fh, raw, st.st_size, 0);
        crypto_secretbox_open_easy(old_plain, raw + NONCE_BYTES, old_plain_len, raw, KEY);
        free(raw);
    }

    // Модифицируем данные
    unsigned long long new_len = offset + size;
    if (new_len > old_plain_len) new_len = new_len; // растягиваем если нужно
    else new_len = old_plain_len;

    unsigned char *new_plain = calloc(new_len, 1);
    memcpy(new_plain, old_plain, old_plain_len);
    memcpy(new_plain + offset, buf, size);

    // Шифруем
    unsigned char nonce[NONCE_BYTES];
    randombytes_buf(nonce, NONCE_BYTES);
    unsigned long long cipher_len = new_len + crypto_secretbox_MACBYTES;
    unsigned char *cipher = malloc(NONCE_BYTES + cipher_len);
    memcpy(cipher, nonce, NONCE_BYTES);
    crypto_secretbox_easy(cipher + NONCE_BYTES, new_plain, new_len, nonce, KEY);

    pwrite(fi->fh, cipher, NONCE_BYTES + cipher_len, 0);
    ftruncate(fi->fh, NONCE_BYTES + cipher_len);

    free(old_plain); free(new_plain); free(cipher);
    return size;
}

static int encfs_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    char raw[PATH_MAX];
    get_raw_path(path, raw);
    int fd = open(raw, fi->flags | O_CREAT, mode);
    if (fd == -1) return -errno;
    fi->fh = fd;

    // Создаём пустой файл с nonce + ciphertext(0 bytes)
    unsigned char nonce[NONCE_BYTES];
    randombytes_buf(nonce, NONCE_BYTES);
    unsigned char cipher[crypto_secretbox_MACBYTES];
    crypto_secretbox_easy(cipher, (const unsigned char *)"", 0, nonce, KEY);
    
    pwrite(fd, nonce, NONCE_BYTES, 0);
    pwrite(fd, cipher, sizeof(cipher), NONCE_BYTES);
    return 0;
}

static int encfs_unlink(const char *path) { char raw[PATH_MAX]; get_raw_path(path, raw); return unlink(raw) == -1 ? -errno : 0; }
static int encfs_mkdir(const char *path, mode_t mode) { char raw[PATH_MAX]; get_raw_path(path, raw); return mkdir(raw, mode) == -1 ? -errno : 0; }
static int encfs_rmdir(const char *path) { char raw[PATH_MAX]; get_raw_path(path, raw); return rmdir(raw) == -1 ? -errno : 0; }

static struct fuse_operations encfs_ops = {
    .getattr = encfs_getattr,
    .readdir = encfs_readdir,
    .open    = encfs_open,
    .read    = encfs_read,
    .write   = encfs_write,
    .create  = encfs_create,
    .unlink  = encfs_unlink,
    .mkdir   = encfs_mkdir,
    .rmdir   = encfs_rmdir,
};

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Использование: %s <backend_dir> <mount_point>\n", argv[0]);
        return 1;
    }

    if (sodium_init() < 0) {
        fprintf(stderr, "Ошибка инициализации libsodium\n");
        return 1;
    }

    strncpy(backend, argv[1], PATH_MAX - 1);
    backend[PATH_MAX - 1] = '\0';

    // Запускаем FUSE (single-threaded для отладки)
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    return fuse_main(argc, argv, &encfs_ops, NULL);
}
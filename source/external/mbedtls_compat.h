/*
 * iOS 链接期 mbedTLS 兼容层（KathyEngine）
 *
 * 问题：lime 8.3.2 的 iOS 静态库 liblime.a 是按 mbedTLS 2.x 头文件编译的，
 *       里面的 curl md5/sha256 代码引用 mbedtls_*_ret 系列符号；
 *       而 setup/unix.sh 安装的 libhxcpp 6.0.0-rc.1 自带 mbedtls-3.6.7，
 *       3.x 把这些 _ret 兼容别名删掉了，只保留无后缀函数。
 *       结果：Xcode 链接报 "Undefined symbols for architecture arm64"。
 *
 * 做法：只在 iOS 目标编译 7 个转发函数，把 2.x 名字映射到 3.x 实现。
 *       2.x/3.x 的 mbedtls_md5_context / mbedtls_sha256_context 内存布局一致，
 *       按指针传递是安全的（用不完整类型声明，避免与 mbedTLS 头文件重复定义）。
 *
 * 这个头文件属于项目源码，不修改 haxelib / hxcpp / lime 的任何底层文件。
 * 由 Main.hx 的 `#if ios @:cppInclude(...)` 引入，非 iOS 平台展开为空。
 */
#ifndef KATHYENGINE_MBEDTLS_COMPAT_H
#define KATHYENGINE_MBEDTLS_COMPAT_H

#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE

#include <stddef.h>

struct mbedtls_md5_context;
struct mbedtls_sha256_context;

#ifdef __cplusplus
extern "C" {
#endif

/* --- mbedTLS 3.x 实现，由 libmbedtls_hxcpp.a 提供 --- */
int mbedtls_md5_starts(mbedtls_md5_context *ctx);
int mbedtls_md5_update(mbedtls_md5_context *ctx, const unsigned char *input, size_t ilen);
int mbedtls_md5_finish(mbedtls_md5_context *ctx, unsigned char *output);
int mbedtls_sha256_starts(mbedtls_sha256_context *ctx, int is224);
int mbedtls_sha256_update(mbedtls_sha256_context *ctx, const unsigned char *input, size_t ilen);
int mbedtls_sha256_finish(mbedtls_sha256_context *ctx, unsigned char *output);
int mbedtls_sha256(const unsigned char *input, size_t ilen, unsigned char *output, int is224);

/* --- mbedTLS 2.x 名字，liblime.a 引用这些 --- */
int mbedtls_md5_starts_ret(mbedtls_md5_context *ctx)
{
	return mbedtls_md5_starts(ctx);
}

int mbedtls_md5_update_ret(mbedtls_md5_context *ctx, const unsigned char *input, size_t ilen)
{
	return mbedtls_md5_update(ctx, input, ilen);
}

int mbedtls_md5_finish_ret(mbedtls_md5_context *ctx, unsigned char *output)
{
	return mbedtls_md5_finish(ctx, output);
}

int mbedtls_sha256_starts_ret(mbedtls_sha256_context *ctx, int is224)
{
	return mbedtls_sha256_starts(ctx, is224);
}

int mbedtls_sha256_update_ret(mbedtls_sha256_context *ctx, const unsigned char *input, size_t ilen)
{
	return mbedtls_sha256_update(ctx, input, ilen);
}

int mbedtls_sha256_finish_ret(mbedtls_sha256_context *ctx, unsigned char *output)
{
	return mbedtls_sha256_finish(ctx, output);
}

int mbedtls_sha256_ret(const unsigned char *input, size_t ilen, unsigned char *output, int is224)
{
	return mbedtls_sha256(input, ilen, output, is224);
}

#ifdef __cplusplus
}
#endif

#endif /* TARGET_OS_IPHONE */
#endif /* __APPLE__ */
#endif /* KATHYENGINE_MBEDTLS_COMPAT_H */

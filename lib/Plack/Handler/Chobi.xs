#ifdef __cplusplus
extern "C" {
#endif

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#include <poll.h>
#include <perlio.h>

#ifdef __cplusplus
} /* extern "C" */
#endif

#define NEED_newSVpvn_flags
#include "ppport.h"

#include <sys/uio.h>
#include <errno.h>
#include <limits.h>

#ifndef IOV_MAX
#  ifdef UIO_MAXIOV
#    define IOV_MAX UIO_MAXIOV
#  endif
#endif

#ifndef IOV_MAX
#  error "Unable to determine IOV_MAX from system headers"
#endif

static inline
char *
svpv2char(SV *sv, STRLEN *lp)
{
  if (!SvOK(sv)) {
    sv_setpvn(sv,"",0);
  }
  if (SvGAMAGIC(sv))
    sv = sv_2mortal(newSVsv(sv));
  return SvPV(sv, *lp);
}


static
ssize_t
_write_timeout(const int fileno, const double timeout, struct iovec *iovec, const int iovcnt ) {
    int rv;
    int nfound;
    struct pollfd wfds[1];
  DO_WRITE:
    rv = writev(fileno, iovec, iovcnt);
    if ( rv >= 0 ) {
      return rv;
    }
    if ( rv < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK ) {
      return rv;
    }
  WAIT_WRITE:
    while (1) {
      wfds[0].fd = fileno;
      wfds[0].events = POLLOUT;
      nfound = poll(wfds, 1, (int)timeout*1000);
      if ( nfound == 1 ) {
        break;
      }
      if ( nfound == 0 && errno != EINTR ) {
        return -1;
      }
    }
    goto DO_WRITE;
}


MODULE = Plack::Handler::Chobi    PACKAGE = Plack::Handler::Chobi

PROTOTYPES: DISABLE

unsigned long
write_psgi_response(fileno, timeout, headers, body)
    int fileno
    double timeout
    SV * headers
    AV * body
  PREINIT:
    ssize_t rv;
    ssize_t len;
    ssize_t iovcnt;
    ssize_t vec_offset;
    ssize_t written;
    int count;
    int i;
    struct iovec * v;
  CODE:
    iovcnt = 1 + av_len(body) + 1;
    {
      struct iovec v[iovcnt]; // Needs C99 compiler
      v[0].iov_base = svpv2char(headers, &len);
      v[0].iov_len = len;
      for (i=0; i < av_len(body) + 1; i++ ) {
        v[i+1].iov_base = svpv2char(*av_fetch(body,i,0), &len);
        v[i+1].iov_len = len;
      }

      vec_offset = 0;
      written = 0;
      while ( iovcnt - vec_offset > 0 ) {
        count = (iovcnt > IOV_MAX) ? IOV_MAX : iovcnt;
        rv = _write_timeout(fileno, timeout,  &v[vec_offset], count - vec_offset);
        if ( rv <= 0 ) {
          // error or disconnected
          break;
        }
        written += rv;
        while ( rv > 0 ) {
          if ( rv >= v[vec_offset].iov_len ) {
            rv -= v[vec_offset].iov_len;
            vec_offset++;
          }
          else {
            v[vec_offset].iov_base = (char*)v[vec_offset].iov_base + rv;
            v[vec_offset].iov_len -= rv;
            rv = 0;
          }
        }
      }
    }
    if (rv < 0) XSRETURN_UNDEF;
    RETVAL = (unsigned long) written;

  OUTPUT:
    RETVAL


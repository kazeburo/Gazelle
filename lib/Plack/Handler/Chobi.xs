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

#include <sys/types.h>
#define _GNU_SOURCE             /* See feature_test_macros(7) */
#include <sys/socket.h>
#include <netinet/in.h> 
#include <netinet/tcp.h>

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
int
_accept(int fileno, struct sockaddr *addr, socklen_t *addrlen) {
    int fd;
#ifdef SOCK_NONBLOCK
    fd = accept4(fileno, addr, addrlen, SOCK_CLOEXEC|SOCK_NONBLOCK);
#else
    fd = accept(fileno, addr, addrlen);
#endif
    if (fd < 0) {
      return fd;
    }
#ifndef SOCK_NONBLOCK
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
#endif
    return fd;
}

static AV *psgi_version;

static
ssize_t
_writev_timeout(const int fileno, const double timeout, struct iovec *iovec, const int iovcnt ) {
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

static
ssize_t
_read_timeout(const int fileno, const double timeout, char * read_buf, const int read_len ) {
    int rv;
    int nfound;
    struct pollfd rfds[1];
  DO_READ:
    rfds[0].fd = fileno;
    rfds[0].events = POLLIN;
    rv = read(fileno, read_buf, read_len);
    if ( rv >= 0 ) {
      return rv;
    }
    if ( rv < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK ) {
      return rv;
    }
  WAIT_READ:
    while (1) {
      nfound = poll(rfds, 1, (int)timeout*1000);
      if ( nfound == 1 ) {
        break;
      }
      if ( nfound == 0 && errno != EINTR ) {
        return -1;
      }
    }
    goto DO_READ;
}

static
ssize_t
_write_timeout(const int fileno, const double timeout, char * write_buf, const int write_len ) {
    int rv;
    int nfound;
    struct pollfd wfds[1];
  DO_WRITE:
    rv = write(fileno, write_buf, write_len);
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

BOOT:
{
    psgi_version = newAV();
    av_extend(psgi_version, 2);
    (void)av_push(psgi_version,newSViv(1));
    (void)av_push(psgi_version,newSViv(1));
    SvREADONLY_on((SV*)psgi_version);
}

SV *
accept_psgi(fileno, timeout, tcp, host, port)
    int fileno
    double timeout
    int tcp
    SV * host
    SV * port
PREINIT:
    int fd;
    struct sockaddr_in cliaddr;
    socklen_t len = sizeof(cliaddr);
    char read_buf[16384];
    HV * env;
    int flag = 1;
    ssize_t rv = 0;
PPCODE:
{
    /* if ( my ($conn, $buf, $env) = accept_buffer(fileno($server),timeout,tcp,host,port) */

    fd = _accept(fileno, (struct sockaddr *)&cliaddr, &len);
    /* endif */
    if (fd < 0) {
      goto badexit;
    }

    rv = _read_timeout(fd, timeout, &read_buf[0], 16384);
    // printf("fd:%d rv:%ld %f %d\n",fd,rv,timeout);
    if ( rv <= 0 ) {
      close(fd);
      goto badexit;
    }

    env = newHV();

    if ( tcp == 1 ) {
      setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (char*)&flag, sizeof(int));
      (void)hv_stores(env,"REMOTE_ADDR",newSVpv(inet_ntoa(cliaddr.sin_addr),0));
      (void)hv_stores(env,"REMOTE_PORT",newSViv(cliaddr.sin_port));
    }
    else {
      (void)hv_stores(env,"REMOTE_ADDR",newSV(0));
      (void)hv_stores(env,"REMOTE_PORT",newSViv(0));
    }
    (void)hv_stores(env,"SERVER_PORT",          SvREFCNT_inc(port));
    (void)hv_stores(env,"SERVER_NAME",          SvREFCNT_inc(host));
    (void)hv_stores(env,"SCRIPT_NAME",          newSVpv("",0));
    (void)hv_stores(env,"psgi.version",         newRV((SV*)psgi_version));
    (void)hv_stores(env,"psgi.errors",          newRV((SV*)PL_stderrgv));
    (void)hv_stores(env,"psgi.url_scheme",      newSVpvs("http"));
    (void)hv_stores(env,"psgi.run_once",        newSV(0));
    (void)hv_stores(env,"psgi.multithread",     newSV(0));
    (void)hv_stores(env,"psgi.multiprocess",    newSViv(1));
    (void)hv_stores(env,"psgi.streaming",       newSViv(1));
    (void)hv_stores(env,"psgi.nonblocking",     newSV(0));
    (void)hv_stores(env,"psgix.input.buffered", newSViv(1));
    (void)hv_stores(env,"psgix.harakiri",       newSViv(1));

    PUSHs(sv_2mortal(newSViv(fd)));
    PUSHs(sv_2mortal(newSVpv(&read_buf[0], rv)));
    PUSHs(sv_2mortal(newRV_noinc((SV*)env)));
    XSRETURN(3);

    badexit:
    XSRETURN(0);
}

unsigned long
read_timeout(fileno, rbuf, len, offset, timeout)
    int fileno
    SV * rbuf
    ssize_t len
    ssize_t offset
    double timeout
  PREINIT:
    SV * buf;
    char * d;
    ssize_t rv;
    ssize_t buf_len;
  CODE:
    if (!SvROK(rbuf)) croak("buf must be RV");
    buf = SvRV(rbuf);
    if (!SvOK(buf)) {
      sv_setpvn(buf,"",0);
    }
    SvUPGRADE(buf, SVt_PV);
    SvPV_nolen(buf);
    buf_len = SvCUR(buf);
    d = SvGROW(buf, buf_len + len);
    rv = _read_timeout(fileno, timeout, &d[offset], len);
    SvCUR_set(buf, (rv > 0) ? rv + buf_len : buf_len);
    SvPOK_only(buf);
    if (rv < 0) XSRETURN_UNDEF;
    RETVAL = (unsigned long)rv;
  OUTPUT:
    RETVAL

unsigned long
write_timeout(fileno, buf, len, offset, timeout)
    int fileno
    SV * buf
    ssize_t len
    ssize_t offset
    double timeout
  PREINIT:
    char * d;
    ssize_t rv;
  CODE:
    SvUPGRADE(buf, SVt_PV);
    d = SvPV_nolen(buf);
    rv = _write_timeout(fileno, timeout, &d[0], offset);
    if (rv < 0) XSRETURN_UNDEF;
    RETVAL = (unsigned long)rv;
  OUTPUT:
    RETVAL

unsigned long
write_all(fileno, buf, offset, timeout)
    int fileno
    SV * buf
    ssize_t offset
    double timeout
  PREINIT:
    char * d;
    ssize_t buf_len;
    ssize_t rv;
    ssize_t written = 0;
  CODE:
    SvUPGRADE(buf, SVt_PV);
    d = SvPV_nolen(buf);
    buf_len = SvCUR(buf);
    written = 0;
    while ( buf_len > written ) {
      rv = _write_timeout(fileno, timeout, &d[written], buf_len - written);
      if ( rv <= 0 ) {
        break;
      }
      written += rv;
    }
    if (rv < 0) XSRETURN_UNDEF;
    RETVAL = (unsigned long)written;
  OUTPUT:
    RETVAL

void
close_client(fileno)
    int fileno
  CODE:
    close(fileno);

unsigned long
write_psgi_response(fileno, timeout, headers, body)
    int fileno
    double timeout
    SV * headers
    AV * body
  PREINIT:
    ssize_t rv;
    STRLEN len;
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
        rv = _writev_timeout(fileno, timeout,  &v[vec_offset], count - vec_offset);
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


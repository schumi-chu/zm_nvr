//
// ZoneMinder Remote Camera Class Implementation, $Date: 2009-06-03 09:10:28 +0100 (Wed, 03 Jun 2009) $, $Revision: 2907 $
// Copyright (C) 2001-2008 Philip Coombes
// 
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
// 

#include "zm.h"

#if HAVE_LIBAVFORMAT

#include "zm_remote_camera_rtsp.h"
#include "zm_ffmpeg.h"
#include "zm_mem_utils.h"

#include <sys/types.h>
#include <sys/socket.h>

RemoteCameraRtsp::RemoteCameraRtsp( int p_id, const std::string &p_method, const std::string &p_host, const std::string &p_port, const std::string &p_path, int p_width, int p_height, int p_colours, int p_brightness, int p_contrast, int p_hue, int p_colour, bool p_capture ) :
    RemoteCamera( p_id, "rtsp", p_host, p_port, p_path, p_width, p_height, p_colours, p_brightness, p_contrast, p_hue, p_colour, p_capture ),
    rtspThread( 0 )
{
    if ( p_method == "rtpUni" )
        method = RtspThread::RTP_UNICAST;
    else if ( p_method == "rtpMulti" )
        method = RtspThread::RTP_MULTICAST;
    else if ( p_method == "rtpRtsp" )
        method = RtspThread::RTP_RTSP;
    else if ( p_method == "rtpRtspHttp" )
        method = RtspThread::RTP_RTSP_HTTP;
    else
        Fatal( "Unrecognised method '%s' when creating RTSP camera %d", p_method.c_str(), id );

	//schumi#0004, bad h264 implementation
    //Info( "schumi: rtsp method '%s' when creating RTSP camera %d", p_method.c_str(), id );
	#if 0
	h264_buffer=NULL;
	#endif
	//schumi#0004 end
	if ( capture )
	{
		Initialise();
	}
}

RemoteCameraRtsp::~RemoteCameraRtsp()
{
	if ( capture )
	{
		Terminate();
	}
	//schumi#0004, bad h264 implementation
	#if 0
	if (h264_buffer)
		free(h264_buffer);
	#endif
	//schumi#0004 end
}

void RemoteCameraRtsp::Initialise()
{
    RemoteCamera::Initialise();

	int max_size = width*height*colours;

	buffer.size( max_size );

    if ( zm_dbg_level > ZM_DBG_INF )
        av_log_set_level( AV_LOG_DEBUG ); 
    else
        av_log_set_level( AV_LOG_QUIET ); 

    av_register_all();

    frameCount = 0;

    Connect();
}

void RemoteCameraRtsp::Terminate()
{
    avcodec_close( codecContext );
    av_free( codecContext );
    av_free( picture );

    Disconnect();
}

int RemoteCameraRtsp::Connect()
{
    rtspThread = new RtspThread( id, method, protocol, host, port, path, auth );

    rtspThread->start();

    return( 0 );
}

int RemoteCameraRtsp::Disconnect()
{
    if ( rtspThread )
    {
        rtspThread->stop();
        rtspThread->join();
        delete rtspThread;
        rtspThread = 0;
    }
    return( 0 );
}

int RemoteCameraRtsp::PrimeCapture()
{
    Debug( 2, "Waiting for sources" );
    for ( int i = 0; i < 100 && !rtspThread->hasSources(); i++ )
    {
        usleep( 100000 );
    }
    if ( !rtspThread->hasSources() )
        Fatal( "No RTSP sources" );

    Debug( 2, "Got sources" );

    formatContext = rtspThread->getFormatContext();

    // Find the first video stream
    int videoStream=-1;
    for ( int i = 0; i < formatContext->nb_streams; i++ )
        if ( formatContext->streams[i]->codec->codec_type == CODEC_TYPE_VIDEO )
        {
            videoStream = i;
            break;
        }
    if ( videoStream == -1 )
        Fatal( "Unable to locate video stream" );

    // Get a pointer to the codec context for the video stream
    codecContext = formatContext->streams[videoStream]->codec;

    // Find the decoder for the video stream
    codec = avcodec_find_decoder( codecContext->codec_id );
    if ( codec == NULL )
        Fatal( "Unable to locate codec %d decoder", codecContext->codec_id );

	//schumi#0004, bad implementation
	//Info( "schumi: codec %d decoder, w=%d h=%d", codecContext->codec_id, codecContext->width, codecContext->height );
	#if 0
	if ( codecContext->codec_id==28 && !h264_buffer )	// h264 streaming
		h264_buffer=(unsigned char *)malloc(10*BUFSIZ*sizeof(unsigned char));
	#endif
	//schumi#0004 end
    // Open codec
    if ( avcodec_open( codecContext, codec ) < 0 )
        Fatal( "Can't open codec" );

    picture = avcodec_alloc_frame();

    return( 0 );
}

int RemoteCameraRtsp::PreCapture()
{
    if ( !rtspThread->isRunning() )
        return( -1 );
    if ( !rtspThread->hasSources() )
    {
        Error( "Cannot precapture, no RTP sources" );
        return( -1 );
    }
    return( 0 );
}

int RemoteCameraRtsp::Capture( Image &image )
{
	//schumi#0004
#if 0
	static FILE *fp;
	static int tmpi=1;
	if (!fp)
		fp=fopen("/tmp/schumi.avi","wb");
#endif
	//schumi#0004 end
    while ( true )
    {
        buffer.clear();
        if ( !rtspThread->isRunning() )
            break;
        //if ( rtspThread->stopped() )
            //break;
        if ( rtspThread->getFrame( buffer ) )
        {
            Debug( 3, "Read frame %d bytes", buffer.size() );
            Debug( 4, "Address %p", buffer.head() );
            Hexdump( 4, buffer.head(), 16 );

            static AVFrame *tmp_picture = NULL;

            if ( !tmp_picture )
            {
                //if ( c->pix_fmt != pf )
                //{
                    tmp_picture = avcodec_alloc_frame();
                    if ( !tmp_picture )
                    {
                        Fatal( "Could not allocate temporary opicture" );
                    }
                    int size = avpicture_get_size( PIX_FMT_RGB24, width, height);
                    uint8_t *tmp_picture_buf = (uint8_t *)malloc(size);
                    if (!tmp_picture_buf)
                    {
                        av_free( tmp_picture );
                        Fatal( "Could not allocate temporary opicture" );
                    }
                    avpicture_fill( (AVPicture *)tmp_picture, tmp_picture_buf, PIX_FMT_RGB24, width, height );
                //}
            }

            if ( !buffer.size() )
                return( -1 );

            int initialFrameCount = frameCount;
            while ( buffer.size() > 0 )
            {
                int got_picture = false;
				//schumi#0004
				#if 0
				tmpi++;
				if (tmpi>15 /*&& tmpi<17*/)
				{
					fwrite(buffer.head(),sizeof(unsigned char),buffer.size(),fp);
					//fclose(fp);
				}
				#endif
				#if 0	// bad implementation
				if ( codecContext->codec_id==28 && h264_buffer )	// h264 streaming
				{
					int h264_len=ParseH264Buffer(buffer.size(), buffer.head());
                	len = avcodec_decode_video( codecContext, picture, &got_picture, (const unsigned char *)h264_buffer, h264_len );
					#if 1
					if (tmpi>15 /*&& tmpi<17*/)
					{
						fwrite(h264_buffer,sizeof(unsigned char),h264_len,fp);
						//fclose(fp);
					}
					#endif
				}
				else
				#endif
                int len = avcodec_decode_video( codecContext, picture, &got_picture, buffer.head(), buffer.size() );
        		//Info("schumi: len=%d, got=%d, framecount=%d init=%d bufsize=%d"
					//,len,got_picture,frameCount,initialFrameCount,buffer.size());
                if ( len < 0 )
                {
                    if ( frameCount > initialFrameCount )
                    {
                        // Decoded at least one frame
                        return( 0 );
                    }
                    Error( "Error while decoding frame %d", frameCount );
                    Hexdump( ZM_DBG_ERR, buffer.head(), buffer.size()>256?256:buffer.size() );
					#if 0
					if (tmpi>15)
						fwrite(buffer.head(),sizeof(unsigned char),buffer.size(),fp);
					#endif
                    Info( "Error while decoding frame %d, buffer size=%d", frameCount, buffer.size() );
                    buffer.clear();
                    continue;
                    //return( -1 );
                }
				//schumi#0004 end
                Debug( 2, "Frame: %d - %d/%d", frameCount, len, buffer.size() );
                //if ( buffer.size() < 400 )
                    //Hexdump( 0, buffer.head(), buffer.size() );

                if ( got_picture )
                {
                    /* the picture is allocated by the decoder. no need to free it */
                    Debug( 1, "Got picture %d", frameCount );

                    static struct SwsContext *img_convert_ctx = 0;

                    if ( !img_convert_ctx )
                    {
                        img_convert_ctx = sws_getContext( codecContext->width, codecContext->height, codecContext->pix_fmt, width, height, PIX_FMT_RGB24, SWS_BICUBIC, NULL, NULL, NULL );
                        if ( !img_convert_ctx )
                            Fatal( "Unable to initialise image scaling context" );
                    }

                    sws_scale( img_convert_ctx, picture->data, picture->linesize, 0, height, tmp_picture->data, tmp_picture->linesize );

                    image.Assign( width, height, colours, tmp_picture->data[0] );

                    frameCount++;

                    return( 0 );
                }
                else
                {
                    Warning( "Unable to get picture from frame" );
                }
				//schumi#0004
                buffer -= len;
				//buffer-=buffer.size();	// bad implementation
				//schumi#0004 end
            }
        }
    }
    return( -1 );
}

int RemoteCameraRtsp::PostCapture()
{
    return( 0 );
}

//schumi#0004
#if 0
int RemoteCameraRtsp::ParseH264Buffer(int buff_len, unsigned char *buff_start)
{
	unsigned char h264_start_code[4]={0x00, 0x00, 0x00, 0x01};
	int index=0;
	unsigned char *buf=buff_start;

	memcpy(h264_buffer, h264_start_code, sizeof(h264_start_code));
	index+=sizeof(h264_start_code);
	if ( (buf[0]&0x1f)==24 )	// STAP-A type, IDR slices
	{
		int nal_size=(buf[1]<<8)|buf[2];	// sps size
		memcpy(&h264_buffer[index], &buf[3], nal_size);
		index+=nal_size;
		buf+=(3+nal_size);
		memcpy(&h264_buffer[index], h264_start_code, sizeof(h264_start_code));
		index+=sizeof(h264_start_code);
		nal_size=(buf[0]<<8)|buf[1];		// pps size
		memcpy(&h264_buffer[index], &buf[2], nal_size);
		index+=nal_size;
		buf+=(2+nal_size);
		memcpy(&h264_buffer[index], h264_start_code, sizeof(h264_start_code));	// for IDR slices
		index+=sizeof(h264_start_code);
	}
	if ( (buf[0]&0x1f)==28 /*&& ((buf[0]>>5)&0x3)==0x3*/ )	// FU-A type, must do re-fragmentation
	{
		unsigned char pattern[3];
		if ( ((buf[0]>>5)&0x3)==0x3 )
		{
			pattern[0]=0x7c;pattern[1]=0x05;pattern[2]=0x45;	// IDR-slices
		}
		else
		{
			pattern[0]=0x5c;pattern[1]=0x01;pattern[2]=0x41;	// non-IDR-slices
		}
		int k=(buf[0]&0xe0) | (buf[1]&0x1f);	// parsing the real nal unit type
		buf++;
		buf[0]=k;
		k=0;
		int j=buffer.head()+buffer.size()-buf;
		int last_k=0;
		while( --j>1 )
		{
			if ( buf[k]==pattern[0]/*0x7c*/ )
			{
				if ( buf[k+1]==pattern[1]/*0x05*/ )	// middle packet
				{
					if (k<8000)
					{
						k++;
						continue;
					}
					memcpy(&h264_buffer[index], buf, k);
					index+=k;
					buf+=(2+k);
					j-=2;
					k=-1;
					last_k=0;
				}
				else if ( buf[k+1]==pattern[2]/*0x45*/ )	// end packet
				{
					if (k<8000)
					{
						last_k=k;
						k++;
						continue;
					}
					memcpy(&h264_buffer[index], buf, k);
					index+=k;
					buf+=(2+k);
					j-=2;
					last_k=0;
					break;
				}
			}
			k++;
		}
		if (last_k)
		{
			memcpy(&h264_buffer[index], buf, last_k);
			index+=last_k;
			buf+=(2+last_k);
		}
	}
	int left_size=buffer.head()+buffer.size()-buf;
	memcpy(&h264_buffer[index], buf, left_size);
	index+=left_size;

	return index;
}
#endif
//schumi#0004 end
#endif // HAVE_LIBAVFORMAT

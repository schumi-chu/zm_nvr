# ==========================================================================
#
# ZoneMinder Config Admin Module, $Date: 2009-05-25 19:03:46 +0100 (Mon, 25 May 2009) $, $Revision: 2890 $
# Copyright (C) 2001-2008  Philip Coombes
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# ==========================================================================
#
# This module contains the debug definitions and functions used by the rest 
# of the ZoneMinder scripts
#
package ZoneMinder::ConfigAdmin;

use 5.006;
use strict;
use warnings;

require Exporter;
require ZoneMinder::Base;

our @ISA = qw(Exporter ZoneMinder::Base);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use ZoneMinder ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = (
	'data' => [ qw(
		%types
		@options
		%options_hash
	) ],
	'functions' => [ qw(
		loadConfigFromDB
		saveConfigToDB
	) ]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'data'} }, @{ $EXPORT_TAGS{'functions'} } );

our @EXPORT = qw();

our $VERSION = $ZoneMinder::Base::VERSION;

# ==========================================================================
#
# Configuration Administration
#
# ==========================================================================

use ZoneMinder::Config qw(:all);

use Carp;

our $config_header = "src/zm_config_defines.h";
our $config_sql = "db/zm_config.sql";

# Types
our %types =
(
	string => { db_type=>"string", hint=>"string", pattern=>qr|^(.+)$|, format=>q( $1 ) },
	alphanum => { db_type=>"string", hint=>"alphanumeric", pattern=>qr|^([a-zA-Z0-9-_]+)$|, format=>q( $1 ) },
	text => { db_type=>"text", hint=>"free text", pattern=>qr|^(.+)$|, format=>q( $1 ) },
	boolean => { db_type=>"boolean", hint=>"yes|no", pattern=>qr|^([yn])|i, check=>q( $1 ), format=>q( ($1 =~ /^y/) ? "yes" : "no" ) },
	integer => { db_type=>"integer", hint=>"integer", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
	decimal => { db_type=>"decimal", hint=>"decimal", pattern=>qr|^(\d+(?:\.\d+)?)$|, format=>q( $1 ) },
	hexadecimal => { db_type=>"hexadecimal", hint=>"hexadecimal", pattern=>qr|^(?:0x)?([0-9a-f]{1,8})$|, format=>q( "0x".$1 ) },
	tristate => { db_type=>"string", hint=>"auto|yes|no", pattern=>qr|^([ayn])|i, check=>q( $1 ), format=>q( ($1 =~ /^y/) ? "yes" : ($1 =~ /^n/ ? "no" : "auto" ) ) },
	abs_path => { db_type=>"string", hint=>"/absolute/path/to/somewhere", pattern=>qr|^((?:/[^/]*)+?)/?$|, format=>q( $1 ) },
	rel_path => { db_type=>"string", hint=>"relative/path/to/somewhere", pattern=>qr|^((?:[^/].*)?)/?$|, format=>q( $1 ) },
	directory => { db_type=>"string", hint=>"directory", pattern=>qr|^([a-zA-Z0-9-_.]+)$|, format=>q( $1 ) },
	file => { db_type=>"string", hint=>"filename", pattern=>qr|^([a-zA-Z0-9-_.]+)$|, format=>q( $1 ) },
	hostname => { db_type=>"string", hint=>"host.your.domain", pattern=>qr|^([a-zA-Z0-9_.-]+)$|, format=>q( $1 ) },
	url => { db_type=>"string", hint=>"http://host.your.domain/", pattern=>qr|^(?:http://)?(.+)$|, format=>q( "http://".$1 ) },
	email => { db_type=>"string", hint=>"your.name\@your.domain", pattern=>qr|^([a-zA-Z0-9_.-]+)\@([a-zA-Z0-9_.-]+)$|, format=>q( $1\@$2 ) },
);

our @options =
(
	{
		name => "ZM_LANG_DEFAULT",
		default => "en_gb",
		description => "Default language used by web interface",
		help => "ZoneMinder allows the web interface to use languages other than English if the appropriate language file has been created and is present. This option allows you to change the default language that is used from the shipped language, British English, to another language",
		type => $types{string},
		category => "system",
	},
	{
		name => "ZM_OPT_USE_AUTH",
		default => "no",
		description => "Authenticate user logins to ZoneMinder",
		help => "ZoneMinder can run in two modes. The simplest is an entirely unauthenticated mode where anyone can access ZoneMinder and perform all tasks. This is most suitable for installations where the web server access is limited in other ways. The other mode enables user accounts with varying sets of permissions. Users must login or authenticate to access ZoneMinder and are limited by their defined permissions.",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_AUTH_TYPE",
		default => "builtin",
		description => "What is used to authenticate ZoneMinder users",
		help => "ZoneMinder can use two methods to authenticate users when running in authenticated mode. The first is a builtin method where ZoneMinder provides facilities for users to log in and maintains track of their identity. The second method allows interworking with other methods such as http basic authentication which passes an independently authentication 'remote' user via http. In this case ZoneMinder would use the supplied user without additional authentication provided such a user is configured ion ZoneMinder.",
		requires => [ { name=>"ZM_OPT_USE_AUTH", value=>"yes" } ],
		type => { db_type=>"string", hint=>"builtin|remote", pattern=>qr|^([br])|i, format=>q( $1 =~ /^b/ ? "builtin" : "remote" ) },
		category => "system",
	},
	{
		name => "ZM_AUTH_RELAY",
		default => "hashed",
		description => "Method used to relay authentication information",
		help => "When ZoneMinder is running in authenticated mode it can pass user details between the web pages and the back end processes. There are two methods for doing this. This first is to use a time limited hashed string which contains no direct username or password details, the second method is to pass the username and passwords around in plaintext. This method is not recommend except where you do not have the md5 libraries available on your system or you have a completely isolated system with no external access. You can also switch off authentication relaying if your system is isolated in other ways.",
		requires => [ { name=>"ZM_OPT_USE_AUTH", value=>"yes" } ],
		type => { db_type=>"string", hint=>"hashed|plain|none", pattern=>qr|^([hpn])|i, format=>q( ($1 =~ /^h/) ? "hashed" : ($1 =~ /^p/ ? "plain" : "none" ) ) },
		category => "system",
	},
	{
		name => "ZM_AUTH_HASH_SECRET",
		default => "...Change me to something unique...",
		description => "Secret for encoding hashed authentication information",
		help => "When ZoneMinder is running in hashed authenticated mode it is necessary to generate hashed strings containing encrypted sensitive information such as usernames and password. Although these string are reasonably secure the addition of a random secret increases security substantially.",
		requires => [ { name=>"ZM_OPT_USE_AUTH", value=>"yes" }, { name=>"ZM_AUTH_RELAY", value=>"hashed" } ],
		type => $types{string},
		category => "system",
	},
	{
		name => "ZM_AUTH_HASH_IPS",
		default => "yes",
		description => "Include IP addresses in the authentication hash",
		help => "When ZoneMinder is running in hashed authenticated mode it can optionally include the requesting IP address in the resultant hash. This adds an extra level of security as only requests from that address may use that authentication key. However in some circumstances, such as access over mobile networks, the requesting address can change for each request which will cause most requests to fail. This option allows you to control whether IP addresses are included in the authentication hash on your system. If you experience intermitent problems with authentication, switching this option off may help.",
		requires => [ { name=>"ZM_OPT_USE_AUTH", value=>"yes" }, { name=>"ZM_AUTH_RELAY", value=>"hashed" } ],
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_AUTH_HASH_LOGINS",
		default => "no",
		description => "Allow login by authentication hash",
		help => "The normal process for logging into ZoneMinder is via the login screen with username and password. In some circumstances it may be desirable to allow access directly to one or more pages, for instance from a third party application. If this option is enabled then adding an 'auth' parameter to any request will include a shortcut login bypassing the login screen, if not already logged in. As authentication hashes are time and, optionally, IP limited this can allow short-term access to ZoneMinder screens from other web pages etc. In order to use this the calling application will hae to generate the authentication hash itself and ensure it is valid. If you use this option you should ensure that you have modified the ZM_AUTH_HASH_SECRET to somethign unique to your system.",
		requires => [ { name=>"ZM_OPT_USE_AUTH", value=>"yes" }, { name=>"ZM_AUTH_RELAY", value=>"hashed" } ],
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_DIR_EVENTS",
		default => "events",
		description => "Directory where events are stored",
		help => "This is the path to the events directory where all the event images and other miscellaneous files are stored. It is normally given as a subdirectory of the web directory you have specified earlier however if disk space is tight it can reside on another partition in which case you should create a link from that area to the path you give here.",
		type => $types{directory},
		category => "paths",
	},
	{
		name => "ZM_USE_DEEP_STORAGE",
		default => "no",
		description => "Use a deep filesystem hierarchy for events",
		help => "Traditionally ZoneMinder stores all event sfor a monitor in one directory for that monitor. This is simple and efficient except when you have very large amounts of events. Some filesystems are unable to store more than 32k files in one directory and even without this limitation, large numbers of files in a directory can slow creation and deletion of files. This option allows you to select a new method of storing events by year/month/day/hour/min/second which has the effect of separating events out into more directories, resulting in less per directory, and also making it easier to manually navigate to any events that may have happened at a particular time or date. Be warned: deep storage should be considered in beta for now, if you value your data do not select it.",
		type => $types{boolean},
		category => "paths",
	},
	{
		name => "ZM_DIR_IMAGES",
		default => "images",
		description => "Directory where the images that the ZoneMinder client generates are stored",
		help => "ZoneMinder generates a myriad of images, mosty of which are associated with events. For those that aren't this is where they go.",
		type => $types{directory},
		category => "paths",
	},
	{
		name => "ZM_DIR_SOUNDS",
		default => "sounds",
		description => "Directory to the sounds that the ZoneMinder client can use",
		help => "ZoneMinder can optionally play a sound file when an alarm is detected. This indicates where (relative to the web root) to look for this file.",
		type => $types{directory},
		category => "paths",
	},
	{
		name => "ZM_PATH_ZMS",
		default => "/cgi-bin/nph-zms",
		description => "Web path to zms streaming server",
		help => "The ZoneMinder streaming server is required to send streamed images to your browser. It will be installed into the cgi-bin path given at configuration time. This option determines what the web path to the server is rather than the local path on your machine. Ordinarily the streaming server runs in parser-header mode however if you experience problems with streaming you can change this to non-parsed-header (nph) mode by changing 'zms' to 'nph-zms'.",
		type => $types{rel_path},
		category => "paths",
	},
	{
		name => "ZM_CAN_STREAM",
		default => "auto",
		description => "Override the automatic detection of browser streaming capability",
		help => "If you know that your browser can handle image streams of the type 'multipart/x-mixed-replace' but ZoneMinder does not detect this correctly you can set this option to ensure that the stream is delivered with or without the use of the Cambozola plugin. Selecting 'yes' will tell ZoneMinder that your browser can handle the streams natively, 'no' means that it can't and so the plugin will be used while 'auto' lets ZoneMinder decide.",
		type => $types{tristate},
		category => "images",
	},
	{
		name => "ZM_STREAM_METHOD",
		default => "jpeg",
		description => "Which method should be used to send video streams to your browser.",
		help => "ZoneMinder can be configured to use either mpeg encoded video or a series or still jpeg images when sending video streams. This option defines which is used. If you choose mpeg you should ensure that you have the appropriate plugins available on your browser whereas choosing jpeg will work natively on Mozilla and related browsers and with a Java applet on Internet Explorer",
		type => { db_type=>"string", hint=>"mpeg|jpeg", pattern=>qr|^([mj])|i, format=>q( $1 =~ /^m/ ? "mpeg" : "jpeg" ) },
		category => "images",
	},
	{
		name => "ZM_COLOUR_JPEG_FILES",
		default => "yes",
		description => "Colourise greyscale JPEG files",
		help => "Cameras that capture in greyscale can write their captured images to jpeg files with a corresponding greyscale colour space. This saves a small amount of disk space over colour ones. However some tools such as ffmpeg either fail to work with this colour space or have to convert it beforehand. Setting this option to yes uses up a little more space but makes creation of MPEG files much faster.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_ADD_JPEG_COMMENTS",
		default => "no",
		description => "Add jpeg timestamp annotations as file header comments",
		help => "JPEG files may have a number of extra fields added to the file header. The comment field may have any kind of text added. This options allows you to have the same text that is used to annotate the image additionally included as a file header comment. If you archive event images to other locations this may help you locate images for particular events or times if you use software that can read comment headers.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_JPEG_FILE_QUALITY",
		default => "70",
		description => "Set the JPEG quality setting for the saved event files (1-100)",
		help => "When ZoneMinder detects an event it will save the images associated with that event to files. These files are in the JPEG format and can be viewed or streamed later. This option specifies what image quality should be used to save these files. A higher number means better quality but less compression so will take up more disk space and take longer to view over a slow connection. By contrast a low number means smaller, quicker to view, files but at the price of lower quality images. This setting applies to all images written except if the capture image has caused an alarm and the alarm file quality option is set at a higher value when that is used instead.",
		type => $types{integer},
		category => "images",
	},
	{
		name => "ZM_JPEG_ALARM_FILE_QUALITY",
		default => "0",
		description => "Set the JPEG quality setting for the saved event files during an alarm (1-100)",
		help => "This value is equivalent to the regular jpeg file quality setting above except that it only applies to images saved while in an alarm state and then only if this value is set to a higher quality setting than the ordinary file setting. If set to a lower value then it is ignored. Thus leaving it at the default of 0 effectively means to use the regular file quality setting for all saved images. This is to prevent acccidentally saving important images at a worse quality setting.",
		type => $types{integer},
		category => "images",
	},
    # Deprecated, now stream quality
	{
		name => "ZM_JPEG_IMAGE_QUALITY",
		default => "70",
		description => "Set the JPEG quality setting for the streamed 'live' images (1-100)",
		help => "When viewing a 'live' stream for a monitor ZoneMinder will grab an image from the buffer and encode it into JPEG format before sending it. This option specifies what image quality should be used to encode these images. A higher number means better quality but less compression so will take longer to view over a slow connection. By contrast a low number means quicker to view images but at the price of lower quality images. This option does not apply when viewing events or still images as these are usually just read from disk and so will be encoded at the quality specified by the previous options.",
		type => $types{integer},
		category => "hidden",
	},
	{
		name => "ZM_JPEG_STREAM_QUALITY",
		default => "70",
		description => "Set the JPEG quality setting for the streamed 'live' images (1-100)",
		help => "When viewing a 'live' stream for a monitor ZoneMinder will grab an image from the buffer and encode it into JPEG format before sending it. This option specifies what image quality should be used to encode these images. A higher number means better quality but less compression so will take longer to view over a slow connection. By contrast a low number means quicker to view images but at the price of lower quality images. This option does not apply when viewing events or still images as these are usually just read from disk and so will be encoded at the quality specified by the previous options.",
		type => $types{integer},
		category => "images",
	},
	{
		name => "ZM_MPEG_TIMED_FRAMES",
		default => "yes",
		description => "Tag video frames with a timestamp for more realistic streaming",
		help => "When using streamed MPEG based video, either for live monitor streams or events, ZoneMinder can send the streams in two ways. If this option is selected then the timestamp for each frame, taken from it's capture time, is included in the stream. This means that where the frame rate varies, for instance around an alarm, the stream will still maintain it's 'real' timing. If this option is not selected then an approximate frame rate is calculated and that is used to schedule frames instead. This option should be selected unless you encounter problems with your preferred streaming method.",
		requires => [ { name=>"ZM_STREAM_METHOD", value=>"mpeg" } ],
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_MPEG_LIVE_FORMAT",
		default => "swf",
		description => "What format 'live' video streams are played in",
		help => "When using MPEG mode ZoneMinder can output live video. However what formats are handled by the browser varies greatly between machines. This option allows you to specify a video format using a file extension format, so you would just enter the extension of the file type you would like and the rest is determined from that. The default of 'asf' works well under Windows with Windows Media Player but I'm currently not sure what, if anything, works on a Linux platform. If you find out please let me know! If this option is left blank then live streams will revert to being in motion jpeg format",
		requires => [ { name=>"ZM_STREAM_METHOD", value=>"mpeg" } ],
		type => $types{string},
		category => "images",
	},
	{
		name => "ZM_MPEG_REPLAY_FORMAT",
		default => "swf",
		description => "What format 'replay' video streams are played in",
		help => "When using MPEG mode ZoneMinder can replay events in encoded video format. However what formats are handled by the browser varies greatly between machines. This option allows you to specify a video format using a file extension format, so you would just enter the extension of the file type you would like and the rest is determined from that. The default of 'asf' works well under Windows with Windows Media Player and 'mpg', or 'avi' etc should work under Linux. If you knwo any more then please let me know! If this option is left blank then live streams will revert to being in motion jpeg format",
		requires => [ { name=>"ZM_STREAM_METHOD", value=>"mpeg" } ],
		type => $types{string},
		category => "images",
	},
	{
		name => "ZM_RAND_STREAM",
		default => "yes",
		description => "Add a random string to prevent caching of streams",
		help => "Some browsers can cache the streams used by ZoneMinder. In order to prevent his a harmless random string can be appended to the url to make each invocation of the stream appear unique.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_OPT_CAMBOZOLA",
		default => "no",
		description => "Is the (optional) cambozola java streaming client installed",
		help => "Cambozola is a handy low fat cheese flavoured Java applet that ZoneMinder uses to view image streams on browsers such as Internet Explorer that don't natively support this format. If you use this browser it is highly recommended to install this from http://www.charliemouse.com/code/cambozola/  however if it is not installed still images at a lower refresh rate can still be viewed.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_PATH_CAMBOZOLA",
		default => "cambozola.jar",
		description => "Web path to (optional) cambozola java streaming client",
		help => "Cambozola is a handy low fat cheese flavoured Java applet that ZoneMinder uses to view image streams on browsers such as Internet Explorer that don't natively support this format. If you use this browser it is highly recommended to install this from http://www.charliemouse.com/code/cambozola/  however if it is not installed still images at a lower refresh rate can still be viewed. Leave this as 'cambozola.jar' if cambozola is installed in the same directory as the ZoneMinder web client files.",
		requires => [ { name=>"ZM_OPT_CAMBOZOLA", value=>"yes" } ],
		type => $types{rel_path},
		category => "images",
	},
	{
		name => "ZM_RELOAD_CAMBOZOLA",
		default => "0",
		description => "After how many seconds should Cambozola be reloaded in live view",
		help => "Cambozola allows for the viewing of streaming MJPEG however it caches the entire stream into cache space on the computer, setting this to a number > 0 will cause it to automatically reload after that many seconds to avoid filling up a hard drive.",
		type => $types{integer},
		category => "images",
	},
	{
		name => "ZM_TIMESTAMP_ON_CAPTURE",
		default => "yes",
		description => "Timestamp images as soon as they are captured",
		help => "ZoneMinder can add a timestamp to images in two ways. The default method, when this option is set, is that each image is timestamped immediately when captured and so the image held in memory is marked right away. The second method does not timestamp the images until they are either saved as part of an event or accessed over the web. The timestamp used in both methods will contain the same time as this is preserved along with the image. The first method ensures that an image is timestamped regardless of any other circumstances but will result in all images being timestamped even those never saved or viewed. The second method necessitates that saved images are copied before being saved otherwise two timestamps perhaps at different scales may be applied. This has the (perhaps) desirable side effect that the timestamp is always applied at the same resolution so an image that has scaling applied will still have a legible and correctly scaled timestamp.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_LOCAL_BGR_INVERT",
		default => "yes",
		description => "Invert BGR colours to RGB",
		help => "Some cameras or video cards capture images in BGR (Blue-Green-Red) order even when the palette says RGB. If you see strange colours casts on your images then it may be worth trying this option to see if that corrects the issue. Note this option will apply only to local cameras and not those over a network.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_Y_IMAGE_DELTAS",
		default => "yes",
		description => "Calculate image differences using Y channel",
		help => "When ZoneMinder tries to establish the differences between two colour images it generates a greyscale 'delta' image between the two sets of images. In order to do this it determines the differences found between the different RGB colour components and calculates a greyscale value representing this. If this option is set then a calculation will be made to convert each pixel of the image into a brightness value (Y from YUV) and then find the difference between the two. If this option is not set then the resulting difference is determined as the average of the differences of each colour which is a simple calculation. Using the Y value is likely to be more accurate and is up to 15% faster. Only switch this option off if Y based deltas do not work as well for you as RGB ones.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_FAST_IMAGE_BLENDS",
		default => "yes",
		description => "Use a fast algorithm to blend the reference image",
		help => "In most modes of operation ZoneMinder needs to blend the captured image with the stored reference image to update it for the next image. The reference blend percentage specified for the monitor controls how much the new image affects the reference image. There are two methods that are available for this. If this option is set then a basic calculation is applied which though fast and fairly accurate can (due to rounding) mean that the actual range of pixel values in the reference image may be reduced from that in the captured image, e.g. a pixel may only be able to achieve a maximum of say 250 while the captured image is consistently at 255. If you also have a small minimum pixel difference threshold this can cause multiple bogus alarms. The alternative is to switch this option off which stores an additional set of temporary values which eliminate any significant rounding errors. This is more accurate though up to 6 times slower and should not really be necessary unless you find problems with the default method.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_OPT_ADAPTIVE_SKIP",
		default => "yes",
		description => "Should frame analysis try and be efficient in skipping frames",
		help => "In previous versions of ZoneMinder the analysis daemon would attempt to keep up with the capture daemon by processing the last captured frame on each pass. This would sometimes have the undesirable side-effect of missing a chunk of the initial activity that caused the alarm because the pre-alarm frames would all have to be written to disk and the database before processing the next frame, leading to some delay between the first and second event frames. Setting this option enables a newer adaptive algorithm where the analysis daemon attempts to process as many captured frames as possible, only skipping frames when in danger of the capture daemon overwriting yet to be processed frames. This skip is variable depending on the size of the ring buffer and the amount of space left in it. Enabling this option will give you much better coverage of the beginning of alarms whilst biasing out any skipped frames towards the middle or end of the event. However you should be aware that this will have the effect of making the analysis daemon run somewhat behind the capture daemon during events and for particularly fast rates of capture it is possible for the adaptive algorithm to be overwhelmed and not have time to react to a rapid build up of pending frames and thus for a buffer overrun condition to occur.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_BLEND_ALARMED_IMAGES",
		default => "yes",
		description => "Blend alarmed images to update the reference image",
		help => "To detect alarms ZoneMinder compares an image with a reference image which is formed from a composite of the previous images. This option determines whether images that cause events are included in this process. Doing so may increase the precision of the alarmed region but can cause problems if wholescale lighting changes cause alarms as this would not get fed back into the image and an alarm may persist indefinately. A better way to achive the same effect in most cases is to lower substantially the reference blend persentage in specific monitors.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_MAX_SUSPEND_TIME",
		default => "30",
		description => "Maximum time that a monitor may have motion detection suspended",
		help => "ZoneMinder allows monitors to have motion detection to be suspended, for instance while panning a camera. Ordinarily this relies on the operator resuming motion detection afterwards as failure to do so can leave a monitor in a permanently suspended state. This setting allows you to set a maximum time which a camera may be suspended for before it automatically resumes motion detection. This time can be extended by subsequent suspend indications after the first so continuous camera movement will also occur while the monitor is suspended.",
		type => $types{integer},
		category => "config",
	},
    # Deprecated, really no longer necessary
	{
		name => "ZM_OPT_REMOTE_CAMERAS",
		default => "no",
		description => "Are you going to use remote/networked cameras",
		help => "ZoneMinder can work with both local cameras, ie. those attached physically to your computer and remote or network cameras. If you will be using networked cameras select this option.",
		type => $types{boolean},
		category => "hidden",
	},
    # Deprecated, now set on a per monitor basis using the Method field
	{
		name => "ZM_NETCAM_REGEXPS",
		default => "yes",
		description => "Use regular expression matching with network cameras",
		help => "Traditionally ZoneMinder has used complex regular regular expressions to handle the multitude of formats that network cameras produce. In versions from 1.21.1 the default is to use a simpler and faster built in pattern matching methodology. This works well with most networks cameras but if you have problems you can try the older, but more flexible, regular expression based method by selecting this option. Note, to use this method you must have libpcre installed on your system.",
		requires => [ { name => "ZM_OPT_REMOTE_CAMERAS", value => "yes" } ],
		type => $types{boolean},
		category => "hidden",
	},
	{
		name => "ZM_HTTP_VERSION",
		default => "1.1",
		description => "The version of HTTP that ZoneMinder will use to connect",
		help => "ZoneMinder can communicate with network cameras using either of the HTTP/1.1 or HTTP/1.0 standard. A server will normally fall back to the version it supports iwht no problem so this should usually by left at the default. However it can be changed to HTTP/1.0 if necessary to resolve particular issues.",
		type => { db_type=>"string", hint=>"1.1|1.0", pattern=>qr|^(1\.[01])$|, format=>q( $1?$1:"" ) },
		category => "network",
	},
	{
		name => "ZM_HTTP_UA",
		default => "ZoneMinder",
		description => "The user agent that ZoneMinder uses to identify itself",
		help => "When ZoneMinder communicates with remote cameras it will identify itself using this string and it's version number. This is normally sufficient, however if a particular cameras expects only to communicate with certain browsers then this can be changed to a different string identifying ZoneMinder as Internet Explorer or Netscape etc.",
		type => $types{string},
		category => "network",
	},
	{
		name => "ZM_HTTP_TIMEOUT",
		default => "2500",
		description => "How long ZoneMinder waits before giving up on images (milliseconds)",
		help => "When retrieving remote images ZoneMinder will wait for this length of time before deciding that an image is not going to arrive and taking steps to retry. This timeout is in milliseconds (1000 per second) and will apply to each part of an image if it is not sent in one whole chunk.",
		type => $types{integer},
		category => "network",
	},
    {
		name => "ZM_MIN_RTP_PORT",
		default => "40200",
		description => "Minimum port that ZoneMinder will listen for RTP traffic on",
		help => "When ZoneMinder communicates with MPEG4 capable cameras using RTP with the unicast method it must open ports for the camera to connect back to for control and streaming purposes. This setting specifies the minimum port number that ZoneMinder will use. Ordinarily two adjacent ports are used for each camera, one for control packets and one for data packets. This port should be set to an even number, you may also need to open up a hole in your firewall to allow cameras to connect back if you wish to use unicasting.",
		type => $types{integer},
		category => "network",
	},
	{
		name => "ZM_MAX_RTP_PORT",
		default => "40499",
		description => "Maximum port that ZoneMinder will listen for RTP traffic on",
		help => "When ZoneMinder communicates with MPEG4 capable cameras using RTP with the unicast method it must open ports for the camera to connect back to for control and streaming purposes. This setting specifies the maximum port number that ZoneMinder will use. Ordinarily two adjacent ports are used for each camera, one for control packets and one for data packets. This port should be set to an even number, you may also need to open up a hole in your firewall to allow cameras to connect back if you wish to use unicasting. You should also ensure that you have opened up at least two ports for each monitor that will be connecting to unicasting network cameras.",
		type => $types{integer},
		category => "network",
	},
	{
		name => "ZM_OPT_FFMPEG",
		default => "no",
		description => "Is the ffmpeg video encoder/decoder installed",
		help => "ZoneMinder can optionally encode a series of video images into an MPEG encoded movie file for viewing, downloading or storage. This option allows you to specify whether you have the ffmpeg tools installed. Note that creating MPEG files can be fairly CPU and disk intensive and is not a required option as events can still be reviewed as video streams without it.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_PATH_FFMPEG",
		default => "",
		description => "Path to (optional) ffmpeg mpeg encoder",
		help => "This path should point to where ffmpeg has been installed.",
		requires => [ { name=>"ZM_OPT_FFMPEG", value=>"yes" } ],
		type => $types{abs_path},
		category => "images",
	},
	{
		name => "ZM_FFMPEG_INPUT_OPTIONS",
		default => "",
		description => "Additional input options to ffmpeg",
		help => "Ffmpeg can take many options on the command line to control the quality of video produced. This option allows you to specify your own set that apply to the input to ffmpeg (options that are given before the -i option). Check the ffmpeg documentation for a full list of options which may be used here.",
		requires => [ { name=>"ZM_OPT_FFMPEG", value=>"yes" } ],
		type => $types{string},
		category => "images",
	},
	{
		name => "ZM_FFMPEG_OUTPUT_OPTIONS",
		default => "-r 25",
		description => "Additional output options to ffmpeg",
		help => "Ffmpeg can take many options on the command line to control the quality of video produced. This option allows you to specify your own set that apply to the output from ffmpeg (options that are given after the -i option). Check the ffmpeg documentation for a full list of options which may be used here. The most common one will often be to force an output frame rate supported by the video encoder.",
		requires => [ { name=>"ZM_OPT_FFMPEG", value=>"yes" } ],
		type => $types{string},
		category => "images",
	},
	{
		name => "ZM_FFMPEG_FORMATS",
		default => "mpg mpeg wmv asf avi* mov swf 3gp**",
		description => "Formats to allow for ffmpeg video generation",
		help => "Ffmpeg can generate video in many different formats. This option allows you to list the ones you want to be able to select. As new formats are supported by ffmpeg you can add them here and be able to use them immediately. Adding a '*' after a format indicates that this will be the default format used for web video, adding '**' defines the default format for phone video.",
		requires => [ { name=>"ZM_OPT_FFMPEG", value=>"yes" } ],
		type => $types{string},
		category => "images",
	},
	{
		name => "ZM_OPT_NETPBM",
		default => "yes",
		description => "Are the (optional) Netpbm utilities installed",
		help => "For low bandwidth situations ZoneMinder will resize images into thumbnails on the fly before sending them to the browser to reduce the network traffic at the expense of CPU on the server. It uses the Netpbm package to do this and this option should be set to where the binaries from that package are installed. If you do not have it installed it means that the images will always be sent full size and rescaled on your browser which may or not be an issue for you.",
		type => $types{boolean},
		category => "images",
	},
	{
		name => "ZM_PATH_NETPBM",
		default => "/usr/bin",
		description => "Path to (optional) Netpbm utilities",
		help => "For low bandwidth situations ZoneMinder will resize images into thumbnails on the fly before sending them to the browser to reduce the network traffic at the expense of CPU on the server. It uses the Netpbm package to do this and this option should be set to where the binaries from that package are installed. If you do not have it installed it means that the images will always be sent full size and rescaled on your browser which may or not be an issue for you.",
		requires => [ { name=>"ZM_OPT_NETPBM", value=>"yes" } ],
		type => $types{abs_path},
		category => "images",
	},
	{
		name => "ZM_RECORD_EVENT_STATS",
		default => "yes",
		description => "Record event statistical information, switch off if too slow",
		help => "This version of ZoneMinder records detailed information about events in the Stats table. This can help in profiling what the optimum settings are for Zones though this is tricky at present. However in future releases this will be done more easily and intuitively, especially with a large sample of events. The default option of 'yes' allows this information to be collected now in readiness for this but if you are concerned about performance you can switch this off in which case no Stats information will be saved.",
		type => $types{boolean},
		category => "debug",
	},
	{
		name => "ZM_RECORD_DIAG_IMAGES",
		default => "no",
		description => "Record intermediate alarm diagnostic images, can be very slow",
		help => "In addition to recording event statistics you can also record the intermediate diagnostic images that display the results of the various checks and processing that occur when trying to determine if an alarm event has taken place. There are several of these images generated for each frame and zone for each alarm or alert frame so this can have a massive impact on performance. Only switch this setting on for debug or analysis purposes and remember to switch it off again once no longer required.",
		type => $types{boolean},
		category => "debug",
	},
	{
		name => "ZM_EXTRA_DEBUG",
		default => "no",
		description => "Switch additional debugging on",
		help => "ZoneMinder binary components usually have several levels of debug information they can output. Normally this is set to a fairly low level to avoid filling logs too quickly. This options lets you switch on other options that allow you to configure additional debug information to be output. Components will pick up this instruction when they are restarted.",
		type => $types{boolean},
		category => "debug",
	},
	{
		name => "ZM_EXTRA_DEBUG_TARGET",
		default => "",
		description => "What components should have extra debug enabled",
		help => "There are three scopes of debug available. Leaving this option blank means that all components will use extra debug (not recommended). Setting this option to '_<component>', e.g. _zmc, will limit extra debug to that component only. Setting this option to '_<component>_<identity>', e.g. '_zmc_m1' will limit extra debug to that instance of the component only. This is ordinarily what you probably want to do.",
		requires => [ { name => "ZM_EXTRA_DEBUG", value => "yes" } ],
		type => $types{string},
		category => "debug",
	},
	{
		name => "ZM_EXTRA_DEBUG_LEVEL",
		default => 0,
		description => "What level of extra debug should be enabled",
		help => "There are 9 levels of debug available, with higher numbers being more debug and level 0 being no debug. However not all levels are used by all components. Also if there is debug at a high level it is usually likely to be output at such a volume that it may obstruct normal operation. For this reason you should set the level carefully and cautiously until the degree of debug you wish to see is present.",
		requires => [ { name => "ZM_EXTRA_DEBUG", value => "yes" } ],
		type => { db_type=>"integer", hint=>"0|1|2|3|4|5|6|7|8|9", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "debug",
	},
	{
		name => "ZM_EXTRA_DEBUG_LOG",
		default => "/tmp/zm_debug.log+",
		description => "Where extra debug is output to",
		help => "Depending on your system configuration you may find that only errors, warning and informational messages are logged to your system log. This option allows you to specify an additional target for these messages and debug. This also has the advantage of partitioning debug for the component you are tracing, from messages from other components. Be warned however that if this is a simple filename and you are debugging several components then they will all try and write to the same file with undesirable consequences. Appending a '+' to the filename will cause the file to be created with a '.<pid>' suffix containing your process id. In this way debug from each run of a component is kept separate. This is the recommended setting as it will also prevent subsequent runs from overwriting the same log.",
		requires => [ { name => "ZM_EXTRA_DEBUG", value => "yes" } ],
		type => $types{string},
		category => "debug",
	},
	{
		name => "ZM_DUMP_CORES",
		default => "no",
		description => "Create core files on unexpected process failure.",
		help => "When an unrecoverable error occurs in a ZoneMinder binary process is has traditionally been trapped and the details written to logs to aid in remote analysis. However in some cases it is easier to diagnose the error if a core file, which is a memory dump of the process at the time of the error, is created. This can be interactively analysed in the debugger and may reveal more or better information than that available from the logs. This option is recommended for advanced users only otherwise leave at the default. Note using this option to trigger core files will mean that there will be no indication in the binary logs that a process has died, they will just stop, however the zmdc log will still contain an entry. Also note that you may have to explicitly enable core file creation on your system via the 'ulimit -c' command or other means otherwise no file will be created regardless of the value of this option.",
		type => $types{boolean},
		category => "debug",
	},
	{
		name => "ZM_PATH_MAP",
		default => "/dev/shm",
		description => "Path to the mapped memory files that that ZoneMinder can use",
		help => "ZoneMinder has historically used IPC shared memory for shared data between processes. This has it's advantages and limitations. This version of ZoneMinder can use an alternate method, mapped memory, instead with can be enabled with the --enable--mmap directive to configure. This requires less system configuration and is generally more flexible. However it requires each shared data segment to map onto a filesystem file. This option indicates where those mapped files go. You should ensure that this location has sufficient space for these files and for the best performance it should be a tmpfs file system or ramdisk otherwise disk access may render this method slower than the regular shared memory one.",
		type => $types{abs_path},
		category => "paths",
	},
	{
		name => "ZM_PATH_SOCKS",
		default => "/tmp",
		description => "Path to the various Unix domain socket files that ZoneMinder uses",
		help => "ZoneMinder generally uses Unix domain sockets where possible. This reduces the need for port assignments and prevents external applications from possibly compromising the daemons. However each Unix socket requires a .sock file to be created. This option indicates where those socket files go.",
		type => $types{abs_path},
		category => "paths",
	},
	{
		name => "ZM_PATH_LOGS",
		default => "/tmp",
		description => "Path to the various logs that the ZoneMinder daemons generate",
		help => "There are various daemons that are used by ZoneMinder to perform various tasks. Most generate helpful log files and this is where they go. They can be deleted if not required for debugging.",
		type => $types{abs_path},
		category => "paths",
	},
	{
		name => "ZM_PATH_SWAP",
		default => "/tmp",
		description => "Path to location for temporary swap images used in streaming",
		help => "Buffered playback requires temporary swap images to be stored for each instance of the streaming daemons. This option determines where these images will be stored. The images will actually be stored in sub directories beneath this location and will be automatically cleaned up after a period of time.",
		type => $types{abs_path},
		category => "paths",
	},
	{
		name => "ZM_WEB_TITLE_PREFIX",
		default => "ZM",
		description => "The title prefix displayed on each window",
		help => "If you have more than one installation of ZoneMinder it can be helpful to display different titles for each one. Changing this option allows you to customise the window titles to include further information to aid identification.",
		type => $types{string},
		category => "web",
	},
	{
		name => "ZM_WEB_RESIZE_CONSOLE",
		default => "yes",
		description => "Should the console window resize itself to fit",
		help => "Traditionally the main ZoneMinder web console window has resized itself to shrink to a size small enough to list only the monitors that are actually present. This is intended to make the window more unobtrusize but may not be to everyones tastes, especially if opened in a tab in browsers which support this kind if layout. Switch this option off to have the console window size left to the users preference",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_WEB_POPUP_ON_ALARM",
		default => "yes",
		description => "Should the monitor window jump to the top if an alarm occurs",
		help => "When viewing a live monitor stream you can specify whether you want the window to pop to the front if an alarm occurs when the window is minimised or behind another window. This is most useful if your monitors are over doors for example when they can pop up if someone comes to the doorway.",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_OPT_X10",
		default => "no",
		description => "Support interfacing with X10 devices",
		help => "If you have an X10 Home Automation setup in your home you can use ZoneMinder to initiate or react to X10 signals if your computer has the appropriate interface controller. This option indicates whether X10 options will be available in the browser client.",
		type => $types{boolean},
		category => "x10",
	},
	{
		name => "ZM_X10_DEVICE",
		default => "/dev/ttyS0",
		description => "What device is your X10 controller connected on",
		requires => [ { name => "ZM_OPT_X10", value => "yes" } ],
		help => "If you have an X10 controller device (e.g. XM10U) connected to your computer this option details which port it is conected on, the default of /dev/ttyS0 maps to serial or com port 1.",
		type => $types{abs_path},
		category => "x10",
	},
	{
		name => "ZM_X10_HOUSE_CODE",
		default => "A",
		description => "What X10 house code should be used",
		requires => [ { name => "ZM_OPT_X10", value => "yes" } ],
		help => "X10 devices are grouped together by identifying them as all belonging to one House Code. This option details what that is. It should be a single letter between A and P.",
		type => { db_type=>"string", hint=>"A-P", pattern=>qr|^([A-P])|i, format=>q( uc($1) ) },
		category => "x10",
	},
	{
		name => "ZM_X10_DB_RELOAD_INTERVAL",
		default => "60",
		description => "How often (in seconds) the X10 daemon reloads the monitors from the database",
		requires => [ { name => "ZM_OPT_X10", value => "yes" } ],
		help => "The zmx10 daemon periodically checks the database to find out what X10 events trigger, or result from, alarms. This option determines how frequently this check occurs, unless you change this area frequently this can be a fairly large value.",
		type => $types{integer},
		category => "x10",
	},
	{
		name => "ZM_WEB_SOUND_ON_ALARM",
		default => "no",
		description => "Should the monitor window play a sound if an alarm occurs",
		help => "When viewing a live monitor stream you can specify whether you want the window to play a sound to alert you if an alarm occurs.",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_WEB_ALARM_SOUND",
		default => "",
		description => "The sound to play on alarm, put this in the sounds directory",
		help => "You can specify a sound file to play if an alarm occurs whilst you are watching a live monitor stream. So long as your browser understands the format it does not need to be any particular type. This file should be placed in the sounds directory defined earlier.",
		type => $types{file},
		requires => [ { name => "ZM_WEB_SOUND_ON_ALARM", value => "yes" } ],
		category => "web",
	},
	{
		name => "ZM_WEB_COMPACT_MONTAGE",
		default => "no",
		description => "Compact the montage view by removing extra detail",
		help => "The montage view shows the output of all of your active monitors in one window. This include a small menu and status information for each one. This can increase the web traffic and make the window larger than may be desired. Setting this option on removes all this extraneous information and just displays the images.",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_OPT_FAST_DELETE",
		default => "yes",
		description => "Delete only event database records for speed",
		help => "Normally an event created as the result of an alarm consists of entries in one or more database tables plus the various files associated with it. When deleting events in the browser it can take a long time to remove all of this if your are trying to do a lot of events at once. It is recommended that you set this option which means that the browser client only deletes the key entries in the events table, which means the events will no longer appear in the listing, and leaves the zmaudit daemon to clear up the rest later.",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_STRICT_VIDEO_CONFIG",
		default => "yes",
		description => "Allow errors in setting video config to be fatal",
		help => "With some video devices errors can be reported in setting the various video attributes when in fact the operation was successful. Switching this option off will still allow these errors to be reported but will not cause them to kill the video capture daemon. Note however that doing this will cause all errors to be ignored including those which are genuine and which may cause the video capture to not function correctly. Use this option with caution.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_SIGNAL_CHECK_POINTS",
		default => "10",
		description => "How many points in a captured image to check for signal loss",
		help => "For locally attached video cameras ZoneMinder can check for signal loss by looking at a number of random points on each captured image. If all of these points are set to the same fixed colour then the camera is assumed to have lost signal. When this happens any open events are closed and a short one frame signal loss event is generated, as is another when the signal returns. This option defines how many points on each image to check. Note that this is a maximum, any points found to not have the check colour will abort any further checks so in most cases on a couple of points will actually be checked. Network and file based cameras are never checked.",
		type => $types{integer},
		category => "config",
	},
	{
		name => "ZM_V4L_MULTI_BUFFER",
		default => "yes",
		description => "Use more than one buffer for Video 4 Linux devices",
		help => "Performance when using Video 4 Linux devices is usually best if multiple buffers are used allowing the next image to be captured while the previous one is being processed. If you have multiple devices on a card sharing one input that requires switching then this approach can sometimes cause frames from one source to be mixed up with frames from another. Switching this option off prevents multi buffering resulting in slower but more stable image capture. This option is ignored for non-local cameras or if only one input is present on a capture chip. This option addresses a similar problem to the ZM_CAPTURES_PER_FRAME option and you should normally change the value of only one of the options at a time.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_CAPTURES_PER_FRAME",
		default => "1",
		description => "How many images are captured per returned frame, for shared local cameras",
		help => "If you are using cameras attached to a video capture card which forces multiple inputs to share one capture chip, it can sometimes produce images with interlaced frames reversed resulting in poor image quality and a distinctive comb edge appearance. Increasing this setting allows you to force additional image captures before one is selected as the captured frame. This allows the capture hardware to 'settle down' and produce better quality images at the price of lesser capture rates. This option has no effect on (a) network cameras, or (b) where multiple inputs do not share a capture chip. This option addresses a similar problem to the ZM_V4L_MULTI_BUFFER option and you should normally change the value of only one of the options at a time.",
		type => $types{integer},
		category => "config",
	},
	{
		name => "ZM_FILTER_RELOAD_DELAY",
		default => "300",
		description => "How often (in seconds) filters are reloaded in zmfilter",
		help => "ZoneMinder allows you to save filters to the database which allow events that match certain criteria to be emailed, deleted or uploaded to a remote machine etc. The zmfilter daemon loads these and does the actual operation. This option determines how often the filters are reloaded from the database to get the latest versions or new filters. If you don't change filters very often this value can be set to a large value.",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_FILTER_EXECUTE_INTERVAL",
		default => "60",
		description => "How often (in seconds) to run automatic saved filters",
		help => "ZoneMinder allows you to save filters to the database which allow events that match certain criteria to be emailed, deleted or uploaded to a remote machine etc. The zmfilter daemon loads these and does the actual operation. This option determines how often the filters are executed on the saved event in the database. If you want a rapid response to new events this should be a smaller value, however this may increase the overall load on the system and affect performance of other elements.",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_OPT_UPLOAD",
		default => "no",
		description => "Should ZoneMinder support uploading events from filters",
		help => "In ZoneMinder you can create event filters that specify whether events that match certain criteria should be uploaded to a remote server for archiving. This option specifies whether this functionality should be available",
		type => $types{boolean},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_ARCH_FORMAT",
		default => "tar",
		description => "What format the uploaded events should be created in.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		help => "Uploaded events may be stored in either .tar or .zip format, this option specifies which. Note that to use this you will need to have the Archive::Tar and/or Archive::Zip perl modules installed.",
		type => { db_type=>"string", hint=>"tar|zip", pattern=>qr|^([tz])|i, format=>q( $1 =~ /^t/ ? "tar" : "zip" ) },
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_ARCH_COMPRESS",
		default => "no",
		description => "Should archive files be compressed",
		help => "When the archive files are created they can be compressed. However in general since the images are compressed already this saves only a minimal amount of space versus utilising more CPU in their creation. Only enable if you have CPU to waste and are limited in disk space on your remote server or bandwidth.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{boolean},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_ARCH_ANALYSE",
		default => "no",
		description => "Include the analysis files in the archive",
		help => "When the archive files are created they can contain either just the captured frames or both the captured frames and, for frames that caused an alarm, the analysed image with the changed area highlighted. This option controls files are included. Only include analysed frames if you have a high bandwidth connection to the remote server or if you need help in figuring out what caused an alarm in the first place as archives with these files in can be considerably larger.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{boolean},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_HOST",
		default => "",
		description => "The remote server to upload to",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the name, or ip address, of the server to use.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		help => "This is the remote machine that you wish to upload archived events to.",
		type => $types{hostname},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_USER",
		default => "",
		description => "Your ftp username",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the username that ZoneMinder should use to log in for ftp transfer.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{alphanum},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_PASS",
		default => "",
		description => "Your ftp password",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the password that ZoneMinder should use to log in for ftp transfer.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{string},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_LOC_DIR",
		default => "/tmp",
		description => "The local directory in which to create upload files",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the local directory that ZoneMinder should use for temporary upload files. These are files that are created from events, uploaded and then deleted.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{abs_path},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_REM_DIR",
		default => "",
		description => "The remote directory to upload to",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the remote directory that ZoneMinder should use to upload event files to.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{rel_path},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_TIMEOUT",
		default => "120",
		description => "How long to allow the transfer to take for each file",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates the maximum ftp inactivity timeout (in seconds) that should be tolerated before ZoneMinder determiesn that the transfer has failed and closes down the connection.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{integer},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_PASSIVE",
		default => "yes",
		description => "Use passive ftp when uploading",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. This option indicates that ftp transfers should be done in passive mode. This uses a single connection for all ftp activity and, whilst slower than active transfers, is more robust and likely to work from behind filewalls.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		help => "If your computer is behind a firewall or proxy you may need to set FTP to passive mode. In fact for simple transfers it makes little sense to do otherwise anyway but you can set this to 'No' if you wish.",
		type => $types{boolean},
		category => "ftp",
	},
	{
		name => "ZM_UPLOAD_FTP_DEBUG",
		default => "yes",
		description => "Switch ftp debugging on",
		help => "You can use filters to instruct ZoneMinder to upload events to a remote ftp server. If you are having (or expecting) troubles with uploading events then setting this to 'yes' permits additional information to be included in the zmfilter log file.",
		requires => [ { name => "ZM_OPT_UPLOAD", value => "yes" } ],
		type => $types{boolean},
		category => "ftp",
	},
	{
		name => "ZM_OPT_EMAIL",
		default => "no",
		description => "Should ZoneMinder email you details of events that match corresponding filters",
		help => "In ZoneMinder you can create event filters that specify whether events that match certain criteria should have their details emailed to you at a designated email address. This will allow you to be notified of events as soon as they occur and also to quickly view the events directly. This option specifies whether this functionality should be available. The email created with this option can be any size and is intended to be sent to a regular email reader rather than a mobile device.",
		type => $types{boolean},
		category => "mail",
	},
	{
		name => "ZM_EMAIL_ADDRESS",
		default => "",
		description => "The email address to send matching event details to",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" } ],
		help => "This option is used to define the email address that any events that match the appropriate filters will be sent to.",
		type => $types{email},
		category => "mail",
	},
	{
		name => "ZM_EMAIL_TEXT",
		default => 'subject = "ZoneMinder: Alarm - %MN%-%EI% (%ESM% - %ESA% %EFA%)"
body = "
Hello,

An alarm has been detected on your installation of the ZoneMinder.

The details are as follows :-

  Monitor  : %MN%
  Event Id : %EI%
  Length   : %EL%
  Frames   : %EF% (%EFA%)
  Scores   : t%EST% m%ESM% a%ESA%

This alarm was matched by the %FN% filter and can be viewed at %EPS%

ZoneMinder"',
		description => "The text of the email used to send matching event details",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" } ],
		help => "This option is used to define the content of the email that is sent for any events that match the appropriate filters.",
		type => $types{text},
		category => "hidden",
	},
	{
		name => "ZM_EMAIL_SUBJECT",
		default => "ZoneMinder: Alarm - %MN%-%EI% (%ESM% - %ESA% %EFA%)",
		description => "The subject of the email used to send matching event details",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" } ],
		help => "This option is used to define the subject of the email that is sent for any events that match the appropriate filters.",
		type => $types{string},
		category => "mail",
	},
	{
		name => "ZM_EMAIL_BODY",
		default => "
Hello,

An alarm has been detected on your installation of the ZoneMinder.

The details are as follows :-

  Monitor  : %MN%
  Event Id : %EI%
  Length   : %EL%
  Frames   : %EF% (%EFA%)
  Scores   : t%EST% m%ESM% a%ESA%

This alarm was matched by the %FN% filter and can be viewed at %EPS%

ZoneMinder",
		description => "The body of the email used to send matching event details",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" } ],
		help => "This option is used to define the content of the email that is sent for any events that match the appropriate filters.",
		type => $types{text},
		category => "mail",
	},
	{
		name => "ZM_OPT_MESSAGE",
		default => "no",
		description => "Should ZoneMinder message you with details of events that match corresponding filters",
		help => "In ZoneMinder you can create event filters that specify whether events that match certain criteria should have their details sent to you at a designated short message email address. This will allow you to be notified of events as soon as they occur. This option specifies whether this functionality should be available. The email created by this option will be brief and is intended to be sent to an SMS gateway or a minimal mail reader such as a mobile device or phone rather than a regular email reader.",
		type => $types{boolean},
		category => "mail",
	},
	{
		name => "ZM_MESSAGE_ADDRESS",
		default => "",
		description => "The email address to send matching event details to",
		requires => [ { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "This option is used to define the short message email address that any events that match the appropriate filters will be sent to.",
		type => $types{email},
		category => "mail",
	},
	{
		name => "ZM_MESSAGE_TEXT",
		default => 'subject = "ZoneMinder: Alarm - %MN%-%EI%"
body = "ZM alarm detected - %EL% secs, %EF%/%EFA% frames, t%EST%/m%ESM%/a%ESA% score."',
		description => "The text of the message used to send matching event details",
		requires => [ { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "This option is used to define the content of the message that is sent for any events that match the appropriate filters.",
		type => $types{text},
		category => "hidden",
	},
	{
		name => "ZM_MESSAGE_SUBJECT",
		default => "ZoneMinder: Alarm - %MN%-%EI%",
		description => "The subject of the message used to send matching event details",
		requires => [ { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "This option is used to define the subject of the message that is sent for any events that match the appropriate filters.",
		type => $types{string},
		category => "mail",
	},
	{
		name => "ZM_MESSAGE_BODY",
		default => "ZM alarm detected - %EL% secs, %EF%/%EFA% frames, t%EST%/m%ESM%/a%ESA% score.",
		description => "The body of the message used to send matching event details",
		requires => [ { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "This option is used to define the content of the message that is sent for any events that match the appropriate filters.",
		type => $types{text},
		category => "mail",
	},
	{
		name => "ZM_NEW_MAIL_MODULES",
		default => "no",
		description => "Use a newer perl method to send emails",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" }, { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "Traditionally ZoneMinder has used the MIME::Entity perl module to construct and send notification emails and messages. Some people have reported problems with this module not being present at all or flexible enough for their needs. If you are one of those people this option allows you to select a new mailing method using MIME::Lite and Net::SMTP instead. This method was contributed by Ross Melin and should work for everyone but has not been extensively tested so currently is not selected by default.",
		type => $types{boolean},
		category => "mail",
	},
	{
		name => "ZM_EMAIL_HOST",
		default => "localhost",
		description => "The host address of your SMTP mail server",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" }, { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "If you have chosen SMTP as the method by which to send notification emails or messages then this option allows you to choose which SMTP server to use to send them. The default of localhost may work if you have the sendmail, exim or a similar daemon running however you may wish to enter your ISP's SMTP mail server here.",
		type => $types{hostname},
		category => "mail",
	},
	{
		name => "ZM_FROM_EMAIL",
		default => "",
		description => "The email address you wish your event notifications to originate from",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" }, { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "The emails or messages that will be sent to you informing you of events can appear to come from a designated email address to help you with mail filtering etc. An address of something like ZoneMinder\@your.domain is recommended.",
		type => $types{email},
		category => "mail",
	},
	{
		name => "ZM_URL",
		default => "",
		description => "The URL of your ZoneMinder installation",
		requires => [ { name => "ZM_OPT_EMAIL", value => "yes" }, { name => "ZM_OPT_MESSAGE", value => "yes" } ],
		help => "The emails or messages that will be sent to you informing you of events can include a link to the events themselves for easy viewing. If you intend to use this feature then set this option to the url of your installation as it would appear from where you read your email, e.g. http://host.your.domain/zm.php.",
		type => $types{url},
		category => "mail",
	},
	{
		name => "ZM_MAX_RESTART_DELAY",
		default => "600",
		description => "Maximum delay (in seconds) for daemon restart attempts.",
		help => "The zmdc (zm daemon control) process controls when processeses are started or stopped and will attempt to restart any that fail. If a daemon fails frequently then a delay is introduced between each restart attempt. If the daemon stills fails then this delay is increased to prevent extra load being placed on the system by continual restarts. This option controls what this maximum delay is.",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_WATCH_CHECK_INTERVAL",
		default => "10",
		description => "How often to check the capture daemons have not locked up",
		help => "The zmwatch daemon checks the image capture performance of the capture daemons to ensure that they have not locked up (rarely a sync error may occur which blocks indefinately). This option determines how often the daemons are checked.",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_WATCH_MAX_DELAY",
		default => "5",
		description => "The maximum delay allowed since the last captured image",
		help => "The zmwatch daemon checks the image capture performance of the capture daemons to ensure that they have not locked up (rarely a sync error may occur which blocks indefinately). This option determines the maximum delay to allow since the last captured frame. The daemon will be restarted if it has not captured any images after this period though the actual restart may take slightly longer in conjunction with the check interval value above.",
		type => $types{decimal},
		category => "system",
	},
	{

		name => "ZM_RUN_AUDIT",
		default => "yes",
		description => "Run zmaudit to check data consistency",
		help => "The zmaudit daemon exists to check that the saved information in the database and on the filesystem match and are consistent with each other. If an error occurs or if you are using 'fast deletes' it may be that database records are deleted but files remain. In this case, and similar, zmaudit will remove redundant information to synchronise the two data stores. This option controls whether zmaudit is run in the background and performs these checks and fixes continuously. This is recommended for most systems however if you have a very large number of events the process of scanning the database and filesystem may take a long time and impact performance. In this case you may prefer to not have zmaudit running unconditionally and schedule occasional checks at other, more convenient, times.",
		type => $types{boolean},
		category => "system",
	},
	{

		name => "ZM_AUDIT_CHECK_INTERVAL",
		default => "900",
		description => "How often to check database and filesystem consistency",
		help => "The zmaudit daemon exists to check that the saved information in the database and on the filesystem match and are consistent with each other. If an error occurs or if you are using 'fast deletes' it may be that database records are deleted but files remain. In this case, and similar, zmaudit will remove redundant information to synchronise the two data stores. The default check interval of 900 seconds (15 minutes) is fine for most systems however if you have a very large number of events the process of scanning the database and filesystem may take a long time and impact performance. In this case you may prefer to make this interval much larger to reduce the impact on your system. This option determines how often these checks are performed.",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_FORCED_ALARM_SCORE",
		default => "255",
		description => "Score to give forced alarms",
		help => "The 'zmu' utility can be used to force an alarm on a monitor rather than rely on the motion detection algorithms. This option determines what score to give these alarms to distinguish them from regular ones. It must be 255 or less.",
		type => $types{integer},
		category => "config",
	},
	{
		name => "ZM_BULK_FRAME_INTERVAL",
		default => "100",
		description => "How often a bulk frame should be written to the database",
		help => "Traditionally ZoneMinder writes an entry into the Frames database table for each frame that is captured and saved. This works well in motion detection scenarios but when in a DVR situation ('Record' or 'Mocord' mode) this results in a huge number of frame writes and a lot of database and disk bandwidth for very little additional information. Setting this to a non-zero value will enabled ZoneMinder to group these non-alarm frames into one 'bulk' frame entry which saves a lot of bandwidth and space. The only disadvantage of this is that timing information for individual frames is lost but in constant frame rate situations this is usually not significant. This setting is ignored in Modect mode and individual frames are still written if an alarm occurs in Mocord mode also.",
		type => $types{integer},
		category => "config",
	},
	{
		name => "ZM_EVENT_CLOSE_MODE",
		default => "idle",
		description => "When continuous events are closed.",
		help => "When a monitor is running in a continuous recording mode (Record or Mocord) events are usually closed after a fixed period of time (the section length). However in Mocord mode it is possible that motion detection may occur near the end of a section. This option controls what happens when an alarm occurs in Mocord mode. The 'time' setting means that the event will be closed at the end of the section regardless of alarm activity. The 'idle' setting means that the event will be closed at the end of the section if there is no alarm activity occuring at the time otherwise it will be closed once the alarm is over meaning the event may end up being longer than the normal section length. The 'alarm' setting means that if an alarm occurs during the event, the event will be closed once the alarm is over regardless of when this occurs. This has the effect of limiting the number of alarms to one per event and the events will be shorter than the section length if an alarm has occurred.",
		type => $types{boolean},
		type => { db_type=>"string", hint=>"time|idle|alarm", pattern=>qr|^([tia])|i, format=>q( ($1 =~ /^t/) ? "time" : ($1 =~ /^i/ ? "idle" : "time" ) ) },
		category => "config",
	},
    # Deprecated, superseded by event close mode
	{
		name => "ZM_FORCE_CLOSE_EVENTS",
		default => "no",
		description => "Close events at section ends.",
		help => "When a monitor is running in a continuous recording mode (Record or Mocord) events are usually closed after a fixed period of time (the section length). However in Mocord mode it is possible that motion detection may occur near the end of a section and ordinarily this will prevent the event being closed until the motion has ceased. Switching this option on will force the event closed at the specified time regardless of any motion activity.",
		type => $types{boolean},
		category => "hidden",
	},
	{
		name => "ZM_CREATE_ANALYSIS_IMAGES",
		default => "yes",
		description => "Create analysed alarm images with motion outlined",
		help => "By default during an alarm ZoneMinder records both the raw captured image and one that has been analysed and had areas where motion was detected outlined. This can be very useful during zone configuration or in analysing why events occured. However it also incurs some overhead and in a stable system may no longer be necessary. This parameter allows you to switch the generation of these images off.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_WEIGHTED_ALARM_CENTRES",
		default => "no",
		description => "Use a weighted algorithm to calculate the centre of an alarm",
		help => "ZoneMinder will always calculate the centre point of an alarm in a zone to give some indication of where on the screen it is. This can be used by the experimental motion tracking feature or your own custom extensions. In the alarmed or filtered pixels mode this is a simple midpoint between the extents of the detected pxiesl. However in the blob method this can instead be calculated using weighted pixel locations to give more accurate positioning for irregularly shaped blobs. This method, while more precise is also slower and so is turned off by default.",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_EVENT_IMAGE_DIGITS",
		default => "3",
		description => "How many significant digits are used in event image numbering",
		help => "As event images are captured they are stored to the filesystem with a numerical index. By default this index has three digits so the numbers start 001, 002 etc. This works works for most scenarios as events with more than 999 frames are rarely captured. However if you have extremely long events and use external applications then you may wish to increase this to ensure correct sorting of images in listings etc. Warning, increasing this value on a live system may render existing events unviewable as the event will have been saved with the previous scheme. Decreasing this value should have no ill effects.",
		type => $types{integer},
		category => "config",
	},
	{
		name => "ZM_DEFAULT_ASPECT_RATIO",
		default => "4:3",
		description => "The default width:height aspect ratio used in monitors",
		help => "When specifying the dimensions of monitors you can click a checkbox to ensure that the width stays in the correct ratio to the height, or vice versa. This setting allows you to indicate what the ratio of these settings should be. This should be specified in the format <width value>:<height value> and the default of 4:3 normally be acceptable but 11:9 is another common setting. If the checkbox is not clicked when specifying monitor dimensions this setting has no effect.",
		type => $types{string},
		category => "config",
	},
	{
		name => "ZM_USER_SELF_EDIT",
		default => "no",
		description => "Allow unprivileged users to change their details",
		help => "Ordinarily only users with system edit privilege are able to change users details. Switching this option on allows ordinary users to change their passwords and their language settings",
		type => $types{boolean},
		category => "config",
	},
	{
		name => "ZM_OPT_FRAME_SERVER",
		default => "no",
		description => "Should analysis farm out the writing of images to disk",
		#requires => [ { name => "ZM_OPT_ADAPTIVE_SKIP", value => "yes" } ],
		help => "In some circumstances it is possible for a slow disk to take so long writing images to disk that it causes the analysis daemon to fall behind especially during high frame rate events. Setting this option to yes enables a frame server daemon (zmf) which will be sent the images from the analysis daemon and will do the actual writing of images itself freeing up the analysis daemon to get on with other things. Should this transmission fail or other permanent or transient error occur, this function will fall back to the analysis daemon.",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_FRAME_SOCKET_SIZE",
		default => "0",
		description => "Specify the frame server socket buffer size if non-standard",
		requires => [ { name => "ZM_OPT_FRAME_SERVER", value => "yes" } ],
		help => "For large captured images it is possible for the writes from the analysis daemon to the frame server to fail as the amount to be written exceeds the default buffer size. While the images are then written by the analysis daemon so no data is lost, it defeats the object of the frame server daemon in the first place. You can use this option to indicate that a larger buffer size should be used. Note that you may have to change the existing maximum socket buffer size on your system via sysctl (or in /proc/sys/net/core/wmem_max) to allow this new size to be set. Alternatively you can change the default buffer size on your system in the same way in which case that will be used with no change necessary in this option",
		type => $types{integer},
		category => "system",
	},
	{
		name => "ZM_OPT_CONTROL",
		default => "no",
		description => "Support controllable (e.g. PTZ) cameras",
		help => "ZoneMinder includes limited support for controllable cameras. A number of sample protocols are included and others can easily be added. If you wish to control your cameras via ZoneMinder then select this option otherwise if you only have static cameras or use other control methods then leave this option off.",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_OPT_TRIGGERS",
		default => "no",
		description => "Interface external event triggers via socket or device files",
		help => "ZoneMinder can interact with external systems which prompt or cancel alarms. This is done via the zmtrigger.pl script. This option indicates whether you want to use these external triggers. Most people will say no here.",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_CHECK_FOR_UPDATES",
		default => "yes",
		description => "Check with zoneminder.com for updated versions",
		help => "From ZoneMinder version 1.17.0 onwards new versions are expected to be more frequent. To save checking manually for each new version ZoneMinder can check with the zoneminder.com website to determine the most recent release. These checks are infrequent, about once per week, and no personal or system information is transmitted other than your current version number. If you do not wish these checks to take place or your ZoneMinder system has no internet access you can switch these check off with this configuration variable",
		type => $types{boolean},
		category => "system",
	},
	{
		name => "ZM_UPDATE_CHECK_PROXY",
		default => "",
		description => "Proxy url if required to access zoneminder.com",
		help => "If you use a proxy to access the internet then ZoneMinder needs to know so it can access zoneminder.com to check for updates. If you do use a proxy enter the full proxy url here in the form of http://<proxy host>:<proxy port>/",
		type => $types{string},
		category => "system",
	},
	{
		name => "ZM_SHM_KEY",
		default => "0x7a6d0000",
		description => "Shared memory root key to use",
		help => "ZoneMinder uses shared memory to speed up communication between modules. To identify the right area to use shared memory keys are used. This option controls what the base key is, each monitor will have it's Id or'ed with this to get the actual key used. You will not normally need to change this value unless it clashes with another instance of ZoneMinder on the same machine. Only the first four hex digits are used, the lower four will be masked out and ignored.",
		type => $types{hexadecimal},
		category => "system",
	},
    # Deprecated, really no longer necessary
	{
		name => "ZM_WEB_REFRESH_METHOD",
		default => "javascript",
		description => "What method windows should use to refresh themselves",
		help => "Many windows in Javascript need to refresh themselves to keep their information current. This option determines what method they should use to do this. Choosing 'javascript' means that each window will have a short JavaScript statement in with a timer to prompt the refresh. This is the most compatible method. Choosing 'http' means the refresh instruction is put in the HTTP header. This is a cleaner method but refreshes are interrupted or cancelled when a link in the window is clicked meaning that the window will no longer refresh and this would have to be done manually.",
		type => { db_type=>"string", hint=>"javascript|http", pattern=>qr|^([jh])|i, format=>q( $1 =~ /^j/ ? "javascript" : "http" ) },
		category => "hidden",
	},
	{
		name => "ZM_WEB_EVENT_SORT_FIELD",
		default => "DateTime",
		description => "Default field the event lists are sorted by",
		help => "Events in lists can be initially ordered in any way you want. This option controls what field is used to sort them. You can modify this ordering from filters or by clicking on headings in the lists themselves. Bear in mind however that the 'Prev' and 'Next' links, when scrolling through events, relate to the ordering in the lists and so not always to time based ordering.",
		type => { db_type=>"string", hint=>"Id|Name|Cause|MonitorName|DateTime|Length|Frames|AlarmFrames|TotScore|AvgScore|MaxScore", pattern=>qr|.|, format=>q( $1 ) },
		category => "web",
	},
	{
		name => "ZM_WEB_EVENT_SORT_ORDER",
		default => "asc",
		description => "Default order the event lists are sorted by",
		help => "Events in lists can be initially ordered in any way you want. This option controls what order (ascending or descending) is used to sort them. You can modify this ordering from filters or by clicking on headings in the lists themselves. Bear in mind however that the 'Prev' and 'Next' links, when scrolling through events, relate to the ordering in the lists and so not always to time based ordering.",
		type => { db_type=>"string", hint=>"asc|desc", pattern=>qr|^([ad])|i, format=>q( $1 =~ /^a/i ? "asc" : "desc" ) },
		category => "web",
	},
	{
		name => "ZM_WEB_EVENTS_PER_PAGE",
		default => "25",
		description => "How many events to list per page in paged mode",
		help => "In the event list view you can either list all events or just a page at a time. This option controls how many events are listed per page in paged mode and how often to repeat the column headers in non-paged mode.",
		type => $types{integer},
		category => "web",
	},
	{
		name => "ZM_WEB_LIST_THUMBS",
		default => "no",
		description => "Display mini-thumbnails of event images in event lists",
		help => "Ordinarily the event lists just display text details of the events to save space and time. By switching this option on you can also display small thumbnails to help you identify events of interest. The size of these thumbnails is controlled by the following two options.",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_WEB_LIST_THUMB_WIDTH",
		default => "48",
		description => "The width of the thumbnails that appear in the event lists",
		help => "This options controls the width of the thumbnail images that appear in the event lists. It should be fairly small to fit in with the rest of the table. If you prefer you can specify a height instead in the next option but you should only use one of the width or height and the other option should be set to zero. If both width and height are specified then width will be used and height ignored.",
		type => $types{integer},
		requires => [ { name => "ZM_WEB_LIST_THUMBS", value => "yes" } ],
		category => "web",
	},
	{
		name => "ZM_WEB_LIST_THUMB_HEIGHT",
		default => "0",
		description => "The height of the thumbnails that appear in the event lists",
		help => "This options controls the height of the thumbnail images that appear in the event lists. It should be fairly small to fit in with the rest of the table. If you prefer you can specify a width instead in the previous option but you should only use one of the width or height and the other option should be set to zero. If both width and height are specified then width will be used and height ignored.",
		type => $types{integer},
		requires => [ { name => "ZM_WEB_LIST_THUMBS", value => "yes" } ],
		category => "web",
	},
	{
		name => "ZM_WEB_USE_OBJECT_TAGS",
		default => "yes",
		description => "Wrap embed in object tags for media content",
		help => "There are two methods of including media content in web pages. The most common way is use the EMBED tag which is able to give some indication of the type of content. However this is not a standard part of HTML. The official method is to use OBJECT tags which are able to give more information allowing the correct media viewers etc to be loaded. However these are less widely supported and content may be specifically tailored to a particular platform or player. This option controls whether media content is enclosed in EMBED tags only or whether, where appropriate, it is additionally wrapped in OBJECT tags. Currently OBJECT tags are only used in a limited number of circumstances but they may become more widespread in the future. It is suggested that you leave this option on unless you encounter problems playing some content.",
		type => $types{boolean},
		category => "web",
	},
	{
		name => "ZM_WEB_H_REFRESH_MAIN",
		default => "300",
		introduction => "There are now a number of options that are grouped into bandwidth categories, this allows you to configure the ZoneMinder client to work optimally over the various access methods you might to access the client.\n\nThe next few options control what happens when the client is running in 'high' bandwidth mode. You should set these options for when accessing the ZoneMinder client over a local network or high speed link. In most cases the default values will be suitable as a starting point.",
		description => "How often (in seconds) the main console window should refresh itself",
		help => "The main console window lists a general status and the event totals for all monitors. This is not a trivial task and should not be repeated too frequently or it may affect the performance of the rest of the system.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_REFRESH_CYCLE",
		default => "10",
		description => "How often (in seconds) the cycle watch window swaps to the next monitor",
		help => "The cycle watch window is a method of continuously cycling between images from all of your monitors. This option determines how often to refresh with a new image.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_REFRESH_IMAGE",
		default => "5",
		description => "How often (in seconds) the watched image is refreshed (if not streaming)",
		help => "The live images from a monitor can be viewed in either streamed or stills mode. This option determines how often a stills image is refreshed, it has no effect if streaming is selected.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_REFRESH_STATUS",
		default => "3",
		description => "How often (in seconds) the status refreshes itself in the watch window",
		help => "The monitor window is actually made from several frames. The one in the middle merely contains a monitor status which needs to refresh fairly frequently to give a true indication. This option determines that frequency.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_REFRESH_EVENTS",
		default => "30",
		description => "How often (in seconds) the event listing is refreshed in the watch window",
		help => "The monitor window is actually made from several frames. The lower framme contains a listing of the last few events for easy access. This option determines how often this is refreshed.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_DEFAULT_SCALE",
		default => "100",
		description => "What the default scaling factor applied to 'live' or 'event' views is (%)",
		help => "Normally ZoneMinder will display 'live' or 'event' streams in their native size. However if you have monitors with large dimensions or a slow link you may prefer to reduce this size, alternatively for small monitors you can enlarge it. This options lets you specify what the default scaling factor will be. It is expressed as a percentage so 100 is normal size, 200 is double size etc.",
		type => { db_type=>"integer", hint=>"25|33|50|75|100|150|200|300|400", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "highband",
	},
	{
		name => "ZM_WEB_H_DEFAULT_RATE",
		default => "100",
		description => "What the default replay rate factor applied to 'event' views is (%)",
		help => "Normally ZoneMinder will display 'event' streams at their native rate, i.e. as close to real-time as possible. However if you have long events it is often convenient to replay them at a faster rate for review. This option lets you specify what the default replay rate will be. It is expressed as a percentage so 100 is normal rate, 200 is double speed etc.",
		type => { db_type=>"integer", hint=>"25|50|100|150|200|400|1000|2500|5000|10000", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "highband",
	},
	{
		name => "ZM_WEB_H_VIDEO_BITRATE",
		default => "150000",
		description => "What the bitrate of the video encoded stream should be set to",
		help => "When encoding real video via the ffmpeg library a bit rate can be specified which roughly corresponds to the available bandwidth used for the stream. This setting effectively corresponds to a 'quality' setting for the video. A low value will result in a blocky image whereas a high value will produce a clearer view. Note that this setting does not control the frame rate of the video however the quality of the video produced is affected both by this setting and the frame rate that the video is produced at. A higher frame rate at a particular bit rate result in individual frames being at a lower quality.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_VIDEO_MAXFPS",
		default => "15",
		description => "What the maximum frame rate for streamed video should be",
		help => "When using streamed video the main control is the bitrate which determines how much data can be transmitted. However a lower bitrate at high frame rates results in a lower quality image. This option allows you to limit the maximum frame rate to ensure that video quality is maintained. An additional advantage is that encoding video at high frame rates is a processor intensive task when for the most part a very high frame rate offers little perceptible improvement over one that has a more manageable resource requirement. Note, this option is implemented as a cap beyond which binary reduction takes place. So if you have a device capturing at 15fps and set this option to 10fps then the video is not produced at 10fps, but rather at 7.5fps (15 divided by 2) as the final frame rate must be the original divided by a power of 2.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_SCALE_THUMBS",
		default => "no",
		description => "Scale thumbnails in events, bandwidth versus cpu in rescaling",
		help => "If unset, this option sends the whole image to the browser which resizes it in the window. If set the image is scaled down on the server before sending a reduced size image to the browser to conserve bandwidth at the cost of cpu on the server",
		type => $types{boolean},
		requires => [ { name=>"ZM_PATH_NETPBM", value=>"/" } ],
		category => "highband",
	},
	{
		name => "ZM_WEB_H_USE_STREAMS",
		default => "yes",
		description => "Use streaming or stills for live and events views",
		help => "Both the live and events views can use streaming to deliver a smoother feed. However over slow connections or in some other circumstances you can prefer to view stills instead. You can configure this globally with ZM_CAN_STREAM but this option allows you to modify your preference based on the bandwidth setting. Note that this option does not prevent you switching to streaming mode but just selects what the initial default setting is.",
		type => $types{boolean},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_EVENTS_VIEW",
		default => "events",
		description => "What the default view of multiple events should be.",
		help => "Stored events can be viewed in either an events list format or in a timeline based one. This option sets the default view that will be used. Choosing one view here does not prevent the other view being used as it will always be selectable from whichever view is currently being used.",
		type => { db_type=>"string", hint=>"events|timeline", pattern=>qr|^([lt])|i, format=>q( $1 =~ /^e/ ? "events" : "timeline" ) },
		category => "highband",
	},
	{
		name => "ZM_WEB_H_SHOW_PROGRESS",
		default => "yes",
		description => "Show the progress of replay in event view.",
		help => "When viewing events an event navigation panel and progress bar is shown below the event itself. This allows you to jump to specific points in the event, but can can also dynamically update to display the current progress of the event replay itself. This progress is calculated from the actual event duration and is not directly linked to the replay itself, so on limited bandwidth connections may be out of step with the replay. This option allows you to turn off the progress display, whilst still keeping the navigation aspect, where bandwidth prevents it functioning effectively.",
		type => $types{boolean},
		category => "highband",
	},
	{
		name => "ZM_WEB_H_AJAX_TIMEOUT",
		default => "3000",
		description => "How long to wait for Ajax request responses (ms)",
		help => "The newer versions of the live feed and event views use Ajax to request information from the server and populate the views dynamically. This option allows you to specify a timeout if required after which requests are abandoned. A timeout may be necessary if requests would overwise hang such as on a slow connection. This would tend to consume a lot of browser memory and make the interface unresponsive. Ordinarily no requests should timeout so this setting should be set to a value greater than the slowest expected response. This value is in milliseconds but if set to zero then no timeout will be used.",
		type => $types{integer},
		category => "highband",
	},
	{
		name => "ZM_WEB_M_REFRESH_MAIN",
		default => "300",
		description => "How often (in seconds) the main console window should refresh itself",
		help => "The main console window lists a general status and the event totals for all monitors. This is not a trivial task and should not be repeated too frequently or it may affect the performance of the rest of the system.",
		type => $types{integer},
		introduction => "The next few options control what happens when the client is running in 'medium' bandwidth mode. You should set these options for when accessing the ZoneMinder client over a slower cable or DSL link. In most cases the default values will be suitable as a starting point.",
		category => "medband",
	},
	{
		name => "ZM_WEB_M_REFRESH_CYCLE",
		default => "20",
		description => "How often (in seconds) the cycle watch window swaps to the next monitor",
		help => "The cycle watch window is a method of continuously cycling between images from all of your monitors. This option determines how often to refresh with a new image.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_REFRESH_IMAGE",
		default => "10",
		description => "How often (in seconds) the watched image is refreshed (if not streaming)",
		help => "The live images from a monitor can be viewed in either streamed or stills mode. This option determines how often a stills image is refreshed, it has no effect if streaming is selected.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_REFRESH_STATUS",
		default => "5",
		description => "How often (in seconds) the status refreshes itself in the watch window",
		help => "The monitor window is actually made from several frames. The one in the middle merely contains a monitor status which needs to refresh fairly frequently to give a true indication. This option determines that frequency.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_REFRESH_EVENTS",
		default => "60",
		description => "How often (in seconds) the event listing is refreshed in the watch window",
		help => "The monitor window is actually made from several frames. The lower framme contains a listing of the last few events for easy access. This option determines how often this is refreshed.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_DEFAULT_SCALE",
		default => "100",
		description => "What the default scaling factor applied to 'live' or 'event' views is (%)",
		help => "Normally ZoneMinder will display 'live' or 'event' streams in their native size. However if you have monitors with large dimensions or a slow link you may prefer to reduce this size, alternatively for small monitors you can enlarge it. This options lets you specify what the default scaling factor will be. It is expressed as a percentage so 100 is normal size, 200 is double size etc.",
		type => { db_type=>"integer", hint=>"25|33|50|75|100|150|200|300|400", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "medband",
	},
	{
		name => "ZM_WEB_M_DEFAULT_RATE",
		default => "100",
		description => "What the default replay rate factor applied to 'event' views is (%)",
		help => "Normally ZoneMinder will display 'event' streams at their native rate, i.e. as close to real-time as possible. However if you have long events it is often convenient to replay them at a faster rate for review. This option lets you specify what the default replay rate will be. It is expressed as a percentage so 100 is normal rate, 200 is double speed etc.",
		type => { db_type=>"integer", hint=>"25|50|100|150|200|400|1000|2500|5000|10000", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "medband",
	},
	{
		name => "ZM_WEB_M_VIDEO_BITRATE",
		default => "75000",
		description => "What the bitrate of the video encoded stream should be set to",
		help => "When encoding real video via the ffmpeg library a bit rate can be specified which roughly corresponds to the available bandwidth used for the stream. This setting effectively corresponds to a 'quality' setting for the video. A low value will result in a blocky image whereas a high value will produce a clearer view. Note that this setting does not control the frame rate of the video however the quality of the video produced is affected both by this setting and the frame rate that the video is produced at. A higher frame rate at a particular bit rate result in individual frames being at a lower quality.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_VIDEO_MAXFPS",
		default => "10",
		description => "What the maximum frame rate for streamed video should be",
		help => "When using streamed video the main control is the bitrate which determines how much data can be transmitted. However a lower bitrate at high frame rates results in a lower quality image. This option allows you to limit the maximum frame rate to ensure that video quality is maintained. An additional advantage is that encoding video at high frame rates is a processor intensive task when for the most part a very high frame rate offers little perceptible improvement over one that has a more manageable resource requirement. Note, this option is implemented as a cap beyond which binary reduction takes place. So if you have a device capturing at 15fps and set this option to 10fps then the video is not produced at 10fps, but rather at 7.5fps (15 divided by 2) as the final frame rate must be the original divided by a power of 2.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_SCALE_THUMBS",
		default => "yes",
		description => "Scale thumbnails in events, bandwidth versus cpu in rescaling",
		help => "If unset, this option sends the whole image to the browser which resizes it in the window. If set the image is scaled down on the server before sending a reduced size image to the browser to conserve bandwidth at the cost of cpu on the server",
		type => $types{boolean},
		requires => [ { name=>"ZM_PATH_NETPBM", value=>"/" } ],
		category => "medband",
	},
	{
		name => "ZM_WEB_M_USE_STREAMS",
		default => "yes",
		description => "Use streaming or stills for live and events views",
		help => "Both the live and events views can use streaming to deliver a smoother feed. However over slow connections or in some other circumstances you can prefer to view stills instead. You can configure this globally with ZM_CAN_STREAM but this option allows you to modify your preference based on the bandwidth setting. Note that this option does not prevent you switching to streaming mode but just selects what the initial default setting is.",
		type => $types{boolean},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_EVENTS_VIEW",
		default => "events",
		description => "What the default view of multiple events should be.",
		help => "Stored events can be viewed in either an events list format or in a timeline based one. This option sets the default view that will be used. Choosing one view here does not prevent the other view being used as it will always be selectable from whichever view is currently being used.",
		type => { db_type=>"string", hint=>"events|timeline", pattern=>qr|^([lt])|i, format=>q( $1 =~ /^e/ ? "events" : "timeline" ) },
		category => "medband",
	},
	{
		name => "ZM_WEB_M_SHOW_PROGRESS",
		default => "yes",
		description => "Show the progress of replay in event view.",
		help => "When viewing events an event navigation panel and progress bar is shown below the event itself. This allows you to jump to specific points in the event, but can can also dynamically update to display the current progress of the event replay itself. This progress is calculated from the actual event duration and is not directly linked to the replay itself, so on limited bandwidth connections may be out of step with the replay. This option allows you to turn off the progress display, whilst still keeping the navigation aspect, where bandwidth prevents it functioning effectively.",
		type => $types{boolean},
		category => "medband",
	},
	{
		name => "ZM_WEB_M_AJAX_TIMEOUT",
		default => "5000",
		description => "How long to wait for Ajax request responses (ms)",
		help => "The newer versions of the live feed and event views use Ajax to request information from the server and populate the views dynamically. This option allows you to specify a timeout if required after which requests are abandoned. A timeout may be necessary if requests would overwise hang such as on a slow connection. This would tend to consume a lot of browser memory and make the interface unresponsive. Ordinarily no requests should timeout so this setting should be set to a value greater than the slowest expected response. This value is in milliseconds but if set to zero then no timeout will be used.",
		type => $types{integer},
		category => "medband",
	},
	{
		name => "ZM_WEB_L_REFRESH_MAIN",
		default => "300",
		description => "How often (in seconds) the main console window should refresh itself",
		introduction => "The next few options control what happens when the client is running in 'low' bandwidth mode. You should set these options for when accessing the ZoneMinder client over a modem or slow link. In most cases the default values will be suitable as a starting point.",
		help => "The main console window lists a general status and the event totals for all monitors. This is not a trivial task and should not be repeated too frequently or it may affect the performance of the rest of the system.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_REFRESH_CYCLE",
		default => "30",
		description => "How often (in seconds) the cycle watch window swaps to the next monitor",
		help => "The cycle watch window is a method of continuously cycling between images from all of your monitors. This option determines how often to refresh with a new image.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_REFRESH_IMAGE",
		default => "15",
		description => "How often (in seconds) the watched image is refreshed (if not streaming)",
		help => "The live images from a monitor can be viewed in either streamed or stills mode. This option determines how often a stills image is refreshed, it has no effect if streaming is selected.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_REFRESH_STATUS",
		default => "10",
		description => "How often (in seconds) the status refreshes itself in the watch window",
		help => "The monitor window is actually made from several frames. The one in the middle merely contains a monitor status which needs to refresh fairly frequently to give a true indication. This option determines that frequency.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_REFRESH_EVENTS",
		default => "180",
		description => "How often (in seconds) the event listing is refreshed in the watch window",
		help => "The monitor window is actually made from several frames. The lower framme contains a listing of the last few events for easy access. This option determines how often this is refreshed.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_DEFAULT_SCALE",
		default => "100",
		description => "What the default scaling factor applied to 'live' or 'event' views is (%)",
		help => "Normally ZoneMinder will display 'live' or 'event' streams in their native size. However if you have monitors with large dimensions or a slow link you may prefer to reduce this size, alternatively for small monitors you can enlarge it. This options lets you specify what the default scaling factor will be. It is expressed as a percentage so 100 is normal size, 200 is double size etc.",
		type => { db_type=>"integer", hint=>"25|33|50|75|100|150|200|300|400", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_DEFAULT_RATE",
		default => "100",
		description => "What the default replay rate factor applied to 'event' views is (%)",
		help => "Normally ZoneMinder will display 'event' streams at their native rate, i.e. as close to real-time as possible. However if you have long events it is often convenient to replay them at a faster rate for review. This option lets you specify what the default replay rate will be. It is expressed as a percentage so 100 is normal rate, 200 is double speed etc.",
		type => { db_type=>"integer", hint=>"25|50|100|150|200|400|1000|2500|5000|10000", pattern=>qr|^(\d+)$|, format=>q( $1 ) },
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_VIDEO_BITRATE",
		default => "25000",
		description => "What the bitrate of the video encoded stream should be set to",
		help => "When encoding real video via the ffmpeg library a bit rate can be specified which roughly corresponds to the available bandwidth used for the stream. This setting effectively corresponds to a 'quality' setting for the video. A low value will result in a blocky image whereas a high value will produce a clearer view. Note that this setting does not control the frame rate of the video however the quality of the video produced is affected both by this setting and the frame rate that the video is produced at. A higher frame rate at a particular bit rate result in individual frames being at a lower quality.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_VIDEO_MAXFPS",
		default => "5",
		description => "What the maximum frame rate for streamed video should be",
		help => "When using streamed video the main control is the bitrate which determines how much data can be transmitted. However a lower bitrate at high frame rates results in a lower quality image. This option allows you to limit the maximum frame rate to ensure that video quality is maintained. An additional advantage is that encoding video at high frame rates is a processor intensive task when for the most part a very high frame rate offers little perceptible improvement over one that has a more manageable resource requirement. Note, this option is implemented as a cap beyond which binary reduction takes place. So if you have a device capturing at 15fps and set this option to 10fps then the video is not produced at 10fps, but rather at 7.5fps (15 divided by 2) as the final frame rate must be the original divided by a power of 2.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_SCALE_THUMBS",
		default => "yes",
		description => "Scale thumbnails in events, bandwidth versus cpu in rescaling",
		help => "If unset, this option sends the whole image to the browser which resizes it in the window. If set the image is scaled down on the server before sending a reduced size image to the browser to conserve bandwidth at the cost of cpu on the server",
		type => $types{boolean},
		requires => [ { name=>"ZM_PATH_NETPBM", value=>"/" } ],
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_USE_STREAMS",
		default => "yes",
		description => "Use streaming or stills for live and events views",
		help => "Both the live and events views can use streaming to deliver a smoother feed. However over slow connections or in some other circumstances you can prefer to view stills instead. You can configure this globally with ZM_CAN_STREAM but this option allows you to modify your preference based on the bandwidth setting. Note that this option does not prevent you switching to streaming mode but just selects what the initial default setting is.",
		type => $types{boolean},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_EVENTS_VIEW",
		default => "events",
		description => "What the default view of multiple events should be.",
		help => "Stored events can be viewed in either an events list format or in a timeline based one. This option sets the default view that will be used. Choosing one view here does not prevent the other view being used as it will always be selectable from whichever view is currently being used.",
		type => { db_type=>"string", hint=>"events|timeline", pattern=>qr|^([lt])|i, format=>q( $1 =~ /^e/ ? "events" : "timeline" ) },
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_SHOW_PROGRESS",
		default => "no",
		description => "Show the progress of replay in event view.",
		help => "When viewing events an event navigation panel and progress bar is shown below the event itself. This allows you to jump to specific points in the event, but can can also dynamically update to display the current progress of the event replay itself. This progress is calculated from the actual event duration and is not directly linked to the replay itself, so on limited bandwidth connections may be out of step with the replay. This option allows you to turn off the progress display, whilst still keeping the navigation aspect, where bandwidth prevents it functioning effectively.",
		type => $types{boolean},
		category => "lowband",
	},
	{
		name => "ZM_WEB_L_AJAX_TIMEOUT",
		default => "10000",
		description => "How long to wait for Ajax request responses (ms)",
		help => "The newer versions of the live feed and event views use Ajax to request information from the server and populate the views dynamically. This option allows you to specify a timeout if required after which requests are abandoned. A timeout may be necessary if requests would overwise hang such as on a slow connection. This would tend to consume a lot of browser memory and make the interface unresponsive. Ordinarily no requests should timeout so this setting should be set to a value greater than the slowest expected response. This value is in milliseconds but if set to zero then no timeout will be used.",
		type => $types{integer},
		category => "lowband",
	},
	{
		name => "ZM_WEB_P_DEFAULT_RATE",
		default => "100",
		description => "What the default replay rate factor applied to 'event' views is (%)",
		help => "Normally ZoneMinder will display 'event' streams at their native rate, i.e. as close to real-time as possible. However if you have long events it is often convenient to replay them at a faster rate for review. This option lets you specify what the default replay rate will be. It is expressed as a percentage so 100 is normal rate, 200 is double speed etc.",
		type => $types{integer},
		category => "phoneband",
	},
	{
		name => "ZM_WEB_P_SCALE_THUMBS",
		default => "yes",
		description => "Scale thumbnails in events, bandwidth versus cpu in rescaling",
		help => "If unset, this option sends the whole image to the browser which resizes it in the window. If set the image is scaled down on the server before sending a reduced size image to the browser to conserve bandwidth at the cost of cpu on the server",
		type => $types{boolean},
		requires => [ { name=>"ZM_PATH_NETPBM", value=>"/" } ],
		category => "phoneband",
	},
	{
		name => "ZM_WEB_P_AJAX_TIMEOUT",
		default => "10000",
		description => "How long to wait for Ajax request responses (ms)",
		help => "The newer versions of the live feed and event views use Ajax to request information from the server and populate the views dynamically. This option allows you to specify a timeout if required after which requests are abandoned. A timeout may be necessary if requests would overwise hang such as on a slow connection. This would tend to consume a lot of browser memory and make the interface unresponsive. Ordinarily no requests should timeout so this setting should be set to a value greater than the slowest expected response. This value is in milliseconds but if set to zero then no timeout will be used.",
		type => $types{integer},
		category => "phoneband",
	},
	{
		name => "ZM_DYN_LAST_VERSION",
		default => "",
		description => "What the last version of ZoneMinder recorded from zoneminder.com is",
		help => "",
		type => $types{string},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_CURR_VERSION",
		default => "1.24.2",
		description => "What the effective current version of ZoneMinder is, might be different from actual if versions ignored",
		help => "",
		type => $types{string},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_DB_VERSION",
		default => "1.24.2",
		description => "What the version of the database is, from zmupdate",
		help => "",
		type => $types{string},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_LAST_CHECK",
		default => "",
		description => "When the last check for version from zoneminder.com was",
		help => "",
		type => $types{integer},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_NEXT_REMINDER",
		default => "",
		description => "When the earliest time to remind about versions will be",
		help => "",
		type => $types{string},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_DONATE_REMINDER_TIME",
		default => 0,
		description => "When the earliest time to remind about donations will be",
		help => "",
		type => $types{integer},
		readonly => 1,
		category => "dynamic",
	},
	{
		name => "ZM_DYN_SHOW_DONATE_REMINDER",
		default => "yes",
		description => "Remind about donations or not",
		help => "",
		type => $types{boolean},
		readonly => 1,
		category => "dynamic",
	},
);

our %options_hash = map { ( $_->{name}, $_ ) } @options;

sub INIT
{
	# Do some initial data munging to finish the data structures
	# Create option ids
	my $option_id = 0;
	foreach my $option ( @options )
	{
		if ( defined($option->{default}) )
		{
			$option->{value} = $option->{default}
		}
		else
		{
			$option->{value} = '';
		}
		#next if ( $option->{category} eq 'hidden' );
		$option->{id} = $option_id++;
	}
}

sub loadConfigFromDB
{
	print( "Loading config from DB\n" );
	my $dbh = DBI->connect( "DBI:mysql:database=".ZM_DB_NAME.";host=".ZM_DB_HOST, ZM_DB_USER, ZM_DB_PASS );
	
	if ( !$dbh )
	{
		print( "Error: unable to load options from database: $DBI::errstr\n" );
		return( 0 );
	}
	my $sql = "select * from Config";
	my $sth = $dbh->prepare_cached( $sql ) or croak( "Can't prepare '$sql': ".$dbh->errstr() );
	my $res = $sth->execute() or croak( "Can't execute: ".$sth->errstr() );
	my $option_count = 0;
	while( my $config = $sth->fetchrow_hashref() )
	{
		my ( $name, $value ) = ( $config->{Name}, $config->{Value} );
		#print( "Name = '$name'\n" );
		my $option = $options_hash{$name};
		if ( !$option )
		{
			warn( "No option '$name' found, removing" );
			next;
		}
		#next if ( $option->{category} eq 'hidden' );
		if ( defined($value) )
		{
			if ( $option->{type} == $types{boolean} )
			{
				$option->{value} = $value?"yes":"no";
			}
			else
			{
				$option->{value} = $value;
			}
		}
		$option_count++;;
	}
	$sth->finish();
	$dbh->disconnect();
	return( $option_count );
}

sub saveConfigToDB
{
	print( "Saving config to DB\n" );
	my $dbh = DBI->connect( "DBI:mysql:database=".ZM_DB_NAME.";host=".ZM_DB_HOST, ZM_DB_USER, ZM_DB_PASS );

	if ( !$dbh )
	{
		print( "Error: unable to save options to database: $DBI::errstr\n" );
		return( 0 );
	}
	my $sql = "delete from Config";
	my $res = $dbh->do( $sql ) or croak( "Can't do '$sql': ".$dbh->errstr() );

	$sql = "replace into Config set Id = ?, Name = ?, Value = ?, Type = ?, DefaultValue = ?, Hint = ?, Pattern = ?, Format = ?, Prompt = ?, Help = ?, Category = ?, Readonly = ?, Requires = ?";
	my $sth = $dbh->prepare_cached( $sql ) or croak( "Can't prepare '$sql': ".$dbh->errstr() );
	foreach my $option ( @options )
	{
		#next if ( $option->{category} eq 'hidden' );
		#print( $option->{name}."\n" ) if ( !$option->{category} );
		$option->{db_type} = $option->{type}->{db_type};
		$option->{db_hint} = $option->{type}->{hint};
		$option->{db_pattern} = $option->{type}->{pattern};
		$option->{db_format} = $option->{type}->{format};
		if ( $option->{db_type} eq "boolean" )
		{
			$option->{db_value} = ($option->{value} eq "yes")?"1":"0";
		}
		else
		{
			$option->{db_value} = $option->{value};
		}
		if ( my $requires = $option->{requires} )
		{
			$option->{db_requires} = join( ";", map { my $value = $_->{value}; $value = ($value eq "yes")?1:0 if ( $options_hash{$_->{name}}->{db_type} eq "boolean" ); ( "$_->{name}=$value" ) } @$requires );
		}
		else
		{
		}
		my $res = $sth->execute( $option->{id}, $option->{name}, $option->{db_value}, $option->{db_type}, $option->{default}, $option->{db_hint}, $option->{db_pattern}, $option->{db_format}, $option->{description}, $option->{help}, $option->{category}, $option->{readonly}?1:0, $option->{db_requires} ) or croak( "Can't execute: ".$sth->errstr() );
	}
	$sth->finish();
	$dbh->disconnect();
}

1;
__END__

=head1 NAME

ZoneMinder::ConfigAdmin - ZoneMinder Configuration Administration module

=head1 SYNOPSIS

  use ZoneMinder::ConfigAdmin;
  use ZoneMinder::ConfigAdmin qw(:all);

  loadConfigFromDB();
  saveConfigToDB();

=head1 DESCRIPTION

The ZoneMinder:ConfigAdmin module contains the master definition of the ZoneMinder configuration options as well as helper methods. This module is intended for specialist confguration management and would not normally be used by end users.

The configuration held in this module, which was previously in zmconfig.pl, includes the name, default value, description, help text, type and category for each option, as well as a number of additional fields in a small number of cases.

=head1 METHODS

=over 4

=item loadConfigFromDB ();

Loads existing configuration from the database (if any) and merges it with the definitions held in this module. This results in the merging of any new configuration and the removal of any deprecated configuration while preserving the existing values of every else.

=item saveConfigToDB ();

Saves configuration held in memory to the database. The act of loading and saving configuration is a convenient way to ensure that the configuration held in the database corresponds with the most recent definitions and that all components are using the same set of configuration.

=head2 EXPORT

None by default.
The :data tag will export the various configuration data structures
The :functions tag will export the helper functions.
The :all tag will export all above symbols.


=head1 SEE ALSO

http://www.zoneminder.com

=head1 AUTHOR

Philip Coombes, E<lt>philip.coombes@zoneminder.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2001-2008  Philip Coombes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.


=cut

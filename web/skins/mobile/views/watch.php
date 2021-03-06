<?php
//
// ZoneMinder web watch view file, $Date: 2008-07-25 10:48:16 +0100 (Fri, 25 Jul 2008) $, $Revision: 2612 $
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

if ( !canView( 'Stream' ) )
{
    $_REQUEST['view'] = "error";
    return;
}

$monitor = dbFetchMonitor( $_REQUEST['mid'] );

$zmuCommand = getZmuCommand( " -m ".$_REQUEST['mid']." -s -f" );
$zmuOutput = exec( escapeshellcmd( $zmuCommand ) );
list( $status, $fps ) = split( ' ', $zmuOutput );
$statusString = $SLANG['Unknown'];
$fpsString = "--.--";
$class = "infoText";
if ( $status <= STATE_PREALARM )
{
    $statusString = $SLANG['Idle'];
}
elseif ( $status == STATE_ALARM )
{
    $statusString = $SLANG['Alarm'];
    $class = "errorText";
}
elseif ( $status == STATE_ALERT )
{
    $statusString = $SLANG['Alert'];
    $class = "warnText";
}
elseif ( $status == STATE_TAPE )
{
    $statusString = $SLANG['Record'];
}
$fpsString = sprintf( "%.2f", $fps );

$sql = "select * from Monitors where Function != 'None' order by Sequence";
$monitors = array();
$monIdx = 0;
$maxWidth = 0;
$maxHeight = 0;
foreach( dbFetchAll( $sql ) as $row )
{
    if ( !visibleMonitor( $row['Id'] ) )
    {
        continue;
    }
    if ( isset($monitor['Id']) && $row['Id'] == $monitor['Id'] )
        $monIdx = count($monitors);
    if ( $maxWidth < $row['Width'] ) $maxWidth = $row['Width'];
    if ( $maxHeight < $row['Height'] ) $maxHeight = $row['Height'];
    $monitors[] = $row;
}

//$monitor = $monitors[$monIdx];
$nextMid = $monIdx==(count($monitors)-1)?$monitors[0]['Id']:$monitors[$monIdx+1]['Id'];
$prevMid = $monIdx==0?$monitors[(count($monitors)-1)]['Id']:$monitors[$monIdx-1]['Id'];

$scale = getDeviceScale( $monitor['Width'], $monitor['Height'] );
$imageSrc = getStreamSrc( array( "mode=single", "monitor=".$monitor['Id'], "scale=".$scale ), '&amp;' );

xhtmlHeaders( __FILE__, $monitor['Name'].' - '.$SLANG['Watch'] );
?>
<body>
  <div id="page">
    <div id="content">
      <p class="<?= $class ?>"><?= makeLink( "?view=events&amp;page=1&amp;view=events&amp;page=1&amp;filter%5Bterms%5D%5B0%5D%5Battr%5D%3DMonitorId&amp;filter%5Bterms%5D%5B0%5D%5Bop%5D%3D%3D&amp;filter%5Bterms%5D%5B0%5D%5Bval%5D%3D".$monitor['Id']."&amp;sort_field=Id&amp;sort_desc=1", $monitor['Name'], canView( 'Events' ) ) ?>:&nbsp;<?= $statusString ?>&nbsp;-&nbsp;<?= $fpsString ?>&nbsp;fps</p>
      <p><a href="?view=<?= $_REQUEST['view'] ?>&amp;mid=<?= $monitor['Id'] ?>"><img src="<?= $imageSrc ?>" alt="<?= $monitor['Name'] ?>" width="<?= reScale( $monitor['Width'], $scale ) ?>" height="<?= reScale( $monitor['Height'], $scale ) ?>"/></a></p>
<?php
if ( $nextMid != $monitor['Id'] || $prevMid != $monitor['Id'] )
{
?>
      <div id="contentButtons">
        <a href="?view=<?= $_REQUEST['view'] ?>&amp;mid=<?= $prevMid ?>"><?= $SLANG['Prev'] ?></a>
        <a href="?view=console"><?= $SLANG['Console'] ?></a>
        <a href="?view=<?= $_REQUEST['view'] ?>&amp;mid=<?= $nextMid ?>"><?= $SLANG['Next'] ?></a>
      </div>
<?php
}
?>
    </div>
  </div>
</body>
</html>

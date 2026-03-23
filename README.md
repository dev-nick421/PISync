<p>Whisper based sync for giving your assigned partner PI (which actually works unlike other tools rn)</p>
<div><code>/pi set &lt;n&gt;</code>&mdash;&nbsp;Set your priest/DPS partner name</div>
<div><code>/pi</code>&mdash;&nbsp;Send PI request whisper to partner</div>
<div><code>/pi show / hide</code>&mdash;&nbsp;Toggle the frame</div>
<div><code>/pi lock / unlock</code>&mdash;&nbsp;Lock/unlock frame position</div>
<div><code>/pi reset</code>&mdash;&nbsp;Reset to idle state<br /><br />Working as of 22.03.2026</div>
<div>&nbsp;</div>
<div>Simply target your priest and do "/pi set"</div>
<div>DPS should macro "/pi" and bind it<br /><br />Priest then has to macro his PI like this:<br /><br /></div>
<div><code>#showtooltip Power Infusion </code></div>
<div><code>/cast [@mouseover,help,nodead][@target,help,nodead]&nbsp;Power Infusion</code></div>
<div><code>/pi active</code></div>
<div>&nbsp;</div>
<div>The "/pi active" is the important part here it whispers the DPS back so the timers start in-sync.</div>

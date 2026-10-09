"""Real installed PZ Lua widget classes; Java UI drawing/objects remain stand-ins."""
lua.execute('''
function getISUIStackTrace()return ''end
ISDock={None=0};UIHorizontalAlignment={Left=0}
local function native()
 local state={visible=true,x=0,y=0,width=0,height=0,text='',focused=false}
 return setmetatable({}, {__index=function(_,name)
  return function(self,value,...)
   if name=='setVisible'then assert(type(value)=='boolean');state.visible=value
   elseif name=='setX'then state.x=value elseif name=='setY'then state.y=value
   elseif name=='setWidth'then state.width=value elseif name=='setHeight'then state.height=value
   elseif name=='getX'then return state.x elseif name=='getY'then return state.y
   elseif name=='getWidth'then return state.width elseif name=='getHeight'then return state.height
   elseif name=='SetText'then state.text=value elseif name=='getText'then return state.text
   elseif name=='isVisible' or name=='getIsVisible'then return state.visible
   elseif name=='isFocused'then return state.focused elseif name=='unfocus'then state.focused=false
   elseif name=='isMouseOver'then return false
   elseif name:find('get')==1 or name=='fraction'then return 0 end
  end
 end})
end
UIElement={new=native};UITextBox2={new=native};UITransition={new=native}
UIManager={RemoveElement=function()end,AddUI=function()end}
function getTexture()return native()end
local textManager=getTextManager()
textManager.getFontFromEnum=function()return {getLineHeight=function()return fontHeight end}end
function getTextManager()return textManager end
ISUITextureGetter={checkGetTexture=function(t)return t end}
function getPlayerScreenWidth()return screenWidth end;function getPlayerScreenHeight()return screenHeight end
''')
for name in ['Layout/ISDock','Layout/ISBounds','ISUIElement','ISPanel','ISPanelJoypad','ISScrollBar','ISScrollingListBox','ISButton','ISComboBox','ISTextEntryBox']:
    lua.execute((a.game/'media/lua/client/ISUI'/f'{name}.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod/'client/DeadAirLibrary.lua').read_text(encoding='utf-8'))
lua.execute((mod/'client/MusicianSoundfonts.lua').read_text(encoding='utf-8'))
lua.execute((mod/'client/DeadAirSongEditor.lua').read_text(encoding='utf-8'))
lua.execute('''
local e=DeadAirSongEditor:new(paper(),DeadAirScore.new());e:initialise();e:setVisible(true)
assert(e.grid:getOptionTooltip(1):find('Snap grid'))
e.scaleEnabled=true;e:scaleChanged();e.rootNote.selected=10;e.rootNote.onChange(e.rootNote.target,e.rootNote)
e.details=true;e.showVelocity=true;e:layout();e:prerender();e:render()
assert(e.titleEntry:getText()=='Untitled song');e:blurFields();assert(not e:textFocused())
e:toggleMaximize();e:prerender()
e.hear=false;e:onMouseDown(e.gridX+12,e.gridY+8);e:onMouseUp(0,0);assert(#e.notes==1)
e:selectAll();e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==0)
e.notes={{n=60,t=0,d=96,v=90}}
e.partButton.onclick(e.partButton.target,e.partButton);assert(e.activePart==2 and #e.song.parts==2 and #e.notes==0)
e.instrument.selected=9;e.instrument.onChange(e.instrument.target,e.instrument);assert(e.instrument.selected==9)
e.partPicker.selected=1;e.partPicker.onChange(e.partPicker.target,e.partPicker);assert(e.activePart==1 and e.notes[1].n==60 and e.instrument.selected==1)
e.partPicker.selected=2;e.partPicker.onChange(e.partPicker.target,e.partPicker);assert(e.activePart==2 and #e.notes==0 and e.instrument.selected==9)
e:toggleLibrary();local b=e.libraryPanel;assert(b.source.options[1]:find('Chords'));b:selectRow(1);b:prerender();b.folders.onclick(b.folders.target,b.folders);assert(b.path:isVisible());b:layout();e:prerender();e:toggleLibrary();assert(not b:isVisible())
e.loopButton.onclick(e.loopButton.target,e.loopButton);assert(e:currentClip().loopLength)
e.unrollButton.onclick(e.unrollButton.target,e.unrollButton);assert(not e:currentClip().loopLength)
e.deleteTrackButton.onclick(e.deleteTrackButton.target,e.deleteTrackButton);assert(#e.song.parts==1 and e.notes[1].n==60);e:undo();assert(#e.song.parts==2)
print('PASS: real installed PZ Lua panel/button/combo/text-entry constructors, tooltips, scale and part callbacks, Add part button, layout, rendering calls, text focus, drawing and key dispatch (Java UI stand-ins)')
''')
lua.execute('''
local F=MusicianSoundfonts
local s={loaded=true,revision=1,added='',inspected='bundled',message='Ready',banks={{id='bundled',name='Included'},{id='pack:Test:main',name='Example pack'}},mappings={},presets={{key='0:0:0',name='Piano',bank=0,program=0,drums=false},{key='896:12:0',name='Soft lead',bank=7,program=12,drums=false}}}
for i=1,16 do s.mappings[i]={name='Instrument '..i,bank='',preset=''}end
DeadAirMidi.soundfontState=function()return s end
DeadAirMidi.busy=function()return false end
local registrations,inspection,preview,applied,stopped
DeadAirMidi.soundfontPacks=function(rows)registrations=rows end
DeadAirMidi.soundfontRefresh=function()return true end
DeadAirMidi.soundfontInspect=function(id)inspection=id;return true end
DeadAirMidi.soundfontPreview=function(bank,key,profile)preview={bank,key,profile};return true end
DeadAirMidi.soundfontStopPreview=function()stopped=true end
DeadAirMidi.soundfontApply=function(rows)applied=rows;return true end
assert(not F.registerPack({}))
assert(F.registerPack({modId='Test',key='main',name='Example pack',path='media/soundfonts/Example.sf2'}))
F.registerPack({modId='Test',key='main',name='Renamed pack',path='media/soundfonts/Example.sf2'})
F.sync();assert(#registrations==1 and registrations[1].name=='Renamed pack')
for _,size in ipairs({{1280,720,14},{1920,1080,22},{1024,768,18}})do
 screenWidth,screenHeight,fontHeight=size[1],size[2],size[3]
 local p=MusicianSoundfontPanel:new();p:initialise();p:prerender()
 assert(p.listH>=p.leftRowH and p.rx+p.rw<=p.width and p.statusY+2*p.fontH<p.applyButton.y)
 p:chooseProfile(2);p.selected=2;p.assignButton.onclick(p.assignButton.target,p.assignButton)
 assert(p.draft[2].preset=='896:12:0' and p.dirty and p.draft[1].bank=='')
 p.previewButton.onclick(p.previewButton.target,p.previewButton);assert(preview[3]==1 and preview[2]=='896:12:0')
 p.applyButton.onclick(p.applyButton.target,p.applyButton);assert(applied[2].preset=='896:12:0')
 p.defaultButton.onclick(p.defaultButton.target,p.defaultButton);assert(p.draft[2].bank=='')
 p.search:setText('soft');p:poll();assert(#p.rows==1 and p.rows[1].name=='Soft lead')
 p.bank.selected=2;p.bank.onChange(p.bank.target,p.bank);assert(inspection=='pack:Test:main' and #p.rows==0)
 p:close();assert(stopped and not p:isVisible())
end
print('PASS: soundfont setup through installed game widgets; addon registration, preset filtering, assignment, reset, preview, Apply, close and three screen/font layouts')
''')

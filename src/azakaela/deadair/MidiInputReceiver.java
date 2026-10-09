package azakaela.deadair;

import javax.sound.midi.MidiMessage;
import javax.sound.midi.Receiver;
import javax.sound.midi.ShortMessage;

/** One receiver per connection. Counters observe this receiver, never another MIDI port. */
final class MidiInputReceiver implements Receiver {
    interface Sink { void midi(int command,int channel,int data1,int data2,long now); }
    private final Sink sink;
    private boolean closed;
    private long messages, notes;
    private int lastNote=-1, lastVelocity, lastChannel=-1, channels;
    private String error="";

    MidiInputReceiver(Sink sink) { this.sink=sink; }

    public synchronized void send(MidiMessage message,long timestamp) {
        if(closed || message==null) return;
        messages++;
        int status=message.getStatus(), command=status&0xf0;
        if(status<0x80 || status>=0xf0) return; // Clock, sensing and SysEx are not notes.
        int length=(command==0xc0 || command==0xd0)?2:3;
        if(message.getLength()<length) return;
        int d1,d2;
        if(message instanceof ShortMessage m) { d1=m.getData1();d2=length==3?m.getData2():0; }
        else {
            // A provider may deliver channel messages using its own MidiMessage subclass.
            byte[] bytes=message.getMessage();
            if(bytes.length<length) return;
            d1=bytes[1]&255;d2=length==3?bytes[2]&255:0;
        }
        if(d1>127 || d2>127) return;
        dispatch(status,d1,d2,System.nanoTime());
    }
    synchronized void sendPacked(int word,int length,long receivedAt){
        if(closed)return;
        messages++;
        int status=word&255,command=status&0xf0;
        if(status<0x80 || status>=0xf0)return;
        int expected=(command==0xc0 || command==0xd0)?2:3;
        if(length<expected)return;
        int d1=(word>>>8)&255,d2=expected==3?(word>>>16)&255:0;
        if(d1>127 || d2>127)return;
        dispatch(status,d1,d2,receivedAt);
    }
    private void dispatch(int status,int d1,int d2,long now){
        int channel=status&15,command=status&0xf0;
        if(command==0x90 && d2>0) {
            notes++;lastNote=d1;lastVelocity=d2;lastChannel=channel;channels|=1<<channel;
        }
        try { sink.midi(command,channel,d1,d2,now); }
        catch(RuntimeException e) {
            // Preserve the cause instead of letting a provider callback fail invisibly.
            error=e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage()).replace('\n',' ').replace('\r',' ');
        }
    }
    public synchronized void close() { closed=true; }
    synchronized void fail(String reason){error=reason;}
    synchronized boolean active(){return !closed && error.isEmpty();}
    synchronized long messages(){return messages;}
    synchronized long notes(){return notes;}
    synchronized int lastNote(){return lastNote;}
    synchronized int lastVelocity(){return lastVelocity;}
    synchronized int lastChannel(){return lastChannel;}
    synchronized String error(){return error;}
    synchronized String status(){
        if(closed)return "MIDI receiver closed. Reconnect MIDI.";
        if(!error.isEmpty())return "MIDI receive error: "+error;
        if(notes==0)return "MIDI: "+messages+" messages / 0 notes - waiting for notes";
        StringBuilder seen=new StringBuilder();
        for(int c=0;c<16;c++)if((channels&(1<<c))!=0){if(!seen.isEmpty())seen.append(',');seen.append(c+1);}
        return "MIDI: "+notes+" notes / last "+lastNote+" / velocity "+lastVelocity+" / channels "+seen;
    }
}

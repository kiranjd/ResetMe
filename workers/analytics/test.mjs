import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import worker from './index.mjs';
const client = readFileSync(new URL('../../website/analytics.js',import.meta.url),'utf8');
function request(body, origin='https://kiranjd.github.io') {return new Request('https://example.com/event',{method:'POST',headers:{Origin:origin},body:JSON.stringify(body)});}
test('collector validates origins and events, strips referrer path, separates tests',async()=>{
 const writes=[];const env={DB:{prepare:()=>({bind:(...values)=>({run:async()=>writes.push(values)})})}};
 const body={event:'pageview',path:'/ResetMe/',referrer:'https://example.org/private?q=secret',test:true};
 assert.equal((await worker.fetch(request(body),env)).status,204);
 assert.equal(writes[0][2],'example.org');assert.equal(writes[0][4],1);
 assert.equal((await worker.fetch(request(body,'https://evil.test'),env)).status,403);
 assert.equal((await worker.fetch(request({...body,event:'random'}),env)).status,400);
 assert.equal((await worker.fetch(request({...body,path:'/other/'}),env)).status,400);
 assert.equal(writes.length,1);
});
function run({search='',dnt=false,beacon=true}={}){
 const events=[];let click;const context={location:{hostname:'kiranjd.github.io',pathname:'/ResetMe/',search},navigator:{doNotTrack:dnt?'1':'0',sendBeacon:(url,body)=>{if(beacon)events.push(JSON.parse(body));return beacon;}},document:{referrer:'https://example.org/private?secret=x',addEventListener:(type,fn)=>click=fn},URL,URLSearchParams,fetch:(url,opts)=>{events.push(JSON.parse(opts.body));return Promise.resolve();}};
 vm.runInNewContext(client,context);return {events,click};
}
test('client counts page and click, strips referrer, keeps test events separate',()=>{const x=run({search:'?analytics=test'});assert.equal(x.events[0].event,'pageview');assert.equal(x.events[0].referrer,'https://example.org');assert.equal(x.events[0].test,true);x.click({target:{closest:()=>true}});assert.equal(x.events[1].event,'download');});
test('privacy opt-outs and fallback transport',()=>{assert.equal(run({dnt:true}).events.length,0);assert.equal(run({search:'?analytics=off'}).events.length,0);assert.equal(run({beacon:false}).events.length,1);});

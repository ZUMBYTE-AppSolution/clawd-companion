const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");

function game() {
    const elements = new Map();
    function element(id) {
        if (!elements.has(id)) elements.set(id, { getContext: () => ({}), focus() {} });
        return elements.get(id);
    }
    const context = vm.createContext({
        location: { hash: "" }, URLSearchParams,
        window: { addEventListener() {} },
        document: { querySelector: element, getElementById: element, addEventListener() {} },
        requestAnimationFrame() {}
    });
    const run = code => vm.runInContext(code, context);
    run(readFileSync(require.resolve("../Resources/EndlessArena/arena.js"), "utf8"));
    run('mode="play"; keys.add("KeyD")');
    return run;
}

test("three lives, 100 HP on respawn, final death, fresh restart", () => {
    const run = game();
    assert.equal(run("lives"),3);
    run("damage(100)");
    assert.equal(run("player.hp"),100);
    assert.equal(run("lives"),2);
    run("damage(100)");
    assert.equal(run("lives"),2);
    run("player.shield=0;damage(100);player.shield=0;damage(100)");
    assert.equal(run("mode"),"dead");
    run("toggle()");
    assert.equal(run("mode"),"play");
    assert.equal(run("lives"),3);
});

test("only a cleared fourth wave advances and every second level grants a life", () => {
    const run = game();
    for (let lv=1; lv<=8; lv++) {
        for(let w=1;w<=4;w++) {
            assert.equal(run("level"),lv);
            assert.equal(run("wave"),w);
            if(w===4) {
                assert.equal(run("enemies.find(e=>e.boss).kind"),lv-1);
                run("budget=0;advance(1/60)");
                assert.equal(run("level"),lv);
            }
            run("budget=0;enemies.forEach(e=>e.hp=0);advance(1/60)");
        }
        assert.equal(run("lives"),3+Math.floor(lv/2));
        assert.equal(run("best"),lv*4+1);
    }
});

test("piercing hits multiple targets once each and stops after capacity", () => {
    const run=game();
    run(`budget=1;spawn=30;cooldown=30;
        for(let i=0;i<3;i++){addEnemy(false);Object.assign(enemies[i], {x:100,y:100,hp:50,max:50,kind:0})}
        bullets=[{x:100,y:100,dx:0,dy:0,life:1,left:2,hits:new Set()}];
        advance(1/60);advance(1/60)`);
    assert.deepEqual(Array.from(run("enemies.map(e=>e.hp)")),[36,36,50]);
});

test("area damage affects nearby targets and movement gates local records", () => {
    const run=game();
    run(`keys.clear();mods[1]=1;budget=1;spawn=30;cooldown=30;
        for(let i=0;i<3;i++){addEnemy(false);Object.assign(enemies[i],{x:100+i*22,y:100,hp:50,max:50,kind:0})}
        bullets=[{x:100,y:100,dx:0,dy:0,life:1,left:1,hits:new Set()}];advance(1/60)`);
    assert.deepEqual(Array.from(run("enemies.map(e=>e.hp)")),[36,43,50]);
    assert.equal(run("best"),0);
    run('keys.add("ArrowLeft");advance(1/60)');
    assert.equal(run("best"),1);
});

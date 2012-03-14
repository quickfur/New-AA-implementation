// vim:set ts=4 sw=4 expandtab:
// Developmental version of completely native AA implementation.

version=AAdebug;
version(AAdebug) {
    import std.conv;
    import std.stdio;
}

import core.exception;
import core.memory;

// This is a temporary syntactic sugar hack until we manage to get dmd to
// work with us nicely.
version(unittest)
{
    alias AssociativeArray AA;
}

struct AssociativeArray(Key,Value)
{
private:
    struct Slot
    {
        Slot   *next;
        hash_t  hash;
        Key     key;
        Value   value;

        this(hash_t h, Key k, Value v)
        {
            hash = h;
            key = k;
            value = v;
        }
    }

    struct Impl
    {
        Slot*[]  slots;
        size_t   nodes;

        // Prevent extra allocations for very small AA's.
        Slot*[4] binit;
    }

    // Range interface
    struct Range
    {
        Slot*[] slots;
        Slot* curslot;

        this(Impl *i) pure nothrow @safe
        {
            if (i !is null)
            {
                slots = i.slots;
                nextSlot();
            }
        }

        void nextSlot() pure nothrow @safe
        {
            while (slots.length > 0)
            {
                if (slots[0] !is null)
                {
                    curslot = slots[0];
                    break;
                }
                slots = slots[1..$];
            }
        }

        @property bool empty() pure const nothrow @safe
        {
            return curslot is null;
        }

        @property ref inout(Slot) front() inout pure const nothrow @safe
        {
            assert(curslot);
            return *curslot;
        }

        void popFront() pure @safe nothrow
        {
            assert(curslot);
            curslot = curslot.next;
            if (curslot is null)
            {
                slots = slots[1..$];
                nextSlot();
            }
        }
    }

    // Reference semantics
    Impl *impl;

    // Preset prime hash sizes for auto-rehashing.
    // FIXME: this shouldn't be duplicated for every template instance.
    static immutable size_t[] prime_list = [
                   31UL,
                   97UL,            389UL,
                1_543UL,          6_151UL,
               24_593UL,         98_317UL,
              393_241UL,      1_572_869UL,
            6_291_469UL,     25_165_843UL,
          100_663_319UL,    402_653_189UL,
        1_610_612_741UL,  4_294_967_291UL,
    //  8_589_934_513UL, 17_179_869_143UL
    ];

    static Slot*[] alloc(size_t len) @trusted
    {
        auto slots = new Slot*[len];
        GC.setAttr(&slots, GC.BlkAttr.NO_INTERIOR);
        return slots;
    }

    inout(Slot) *findSlot(in Key key) inout /*pure nothrow*/ @trusted
    {
        if (!impl)
            return null;

        auto keyhash = typeid(key).getHash(&key);
        auto i = keyhash % impl.slots.length;
        inout(Slot)* slot = impl.slots[i];
        while (slot) {
            if (slot.hash == keyhash && typeid(key).equals(&key, &slot.key))
            {
                return slot;
            }
            slot = slot.next;
        }
        return slot;
    }

public:
    @property size_t length() nothrow pure const @safe { return impl.nodes; }

    Value get(in Key key, lazy Value defaultValue) /*pure nothrow*/ const @safe
    {
        auto s = findSlot(key);
        return (s is null) ? defaultValue : s.value;
    }

    Value *opBinaryRight(string op)(in Key key) /*pure*/ @trusted
        if (op=="in")
    {
        auto slot = findSlot(key);
        return (slot) ? &slot.value : null;
    }

    Value opIndex(in Key key, string file=__FILE__, size_t line=__LINE__)
        @safe /*pure*/
    {
        Value *valp = opBinaryRight!"in"(key);
        if (valp is null)
            throw new RangeError(file, line);

        return *valp;
    }

    void opIndexAssign(in Value value, in Key key) @trusted /*pure nothrow*/
        // Why isn't getHash() pure?!
    {
        if (!impl)
        {
            impl = new Impl();
            impl.slots = impl.binit;
        }

        auto keyhash = typeid(key).getHash(&key);
        auto i = keyhash % impl.slots.length;
        Slot *slot = impl.slots[i];

        if (slot is null)
        {
            impl.slots[i] = new Slot(keyhash, key, value);
        }
        else
        {
            for(;;) {
                if (slot.hash==keyhash && typeid(key).equals(&key, &slot.key))
                {
                    slot.value = value;
                    return;
                }
                else if (!slot.next)
                {
                    slot.next = new Slot(keyhash, key, value);
                    break;
                }

                slot = slot.next;
            }
        }

        if (++impl.nodes > 4*impl.slots.length)
        {
            this.rehash;
        }
    }

    int opApply(scope int delegate(ref Value) dg)
    {
        if (impl is null)
            return 0;

        foreach (Slot *slot; impl.slots)
        {
            while (slot)
            {
                auto result = dg(slot.value);
                if (result)
                    return result;

                slot = slot.next;
            }
        }
        return 0;
    }

    int opApply(scope int delegate(ref Key, ref Value) dg)
    {
        if (impl is null)
            return 0;

        foreach (Slot *slot; impl.slots)
        {
            while (slot)
            {
                auto result = dg(slot.key, slot.value);
                if (result)
                    return result;

                slot = slot.next;
            }
        }
        return 0;
    }

    bool opEquals(inout typeof(this) that) inout nothrow pure @safe
    {
        if (impl is that.impl)
            return true;

        if (impl is null || that.impl is null)
            return false;

        if (impl.nodes != that.impl.nodes)
            return false;

        foreach (inout(Slot)* slot; impl.slots)
        {
            while (slot)
            {
                inout(Slot)* s = that.impl.slots[slot.hash % that.impl.slots.length];

                // To be equal, it is enough for one of the target slots to
                // match the current entry.
                while (s)
                {
                    if (slot.key == s.key && slot.value == s.value)
                        break;
                    s = s.next;
                }

                // No match found at all; give up.
                if (!s) return false;

                slot = slot.next;
            }
        }
        return true;
    }

    @property inout(Key)[] keys() inout @trusted
    {
        inout(Key)[] k;
        if (impl !is null)
        {
            // Preallocate output array for efficiency
            k.reserve(impl.nodes);
            foreach (inout(Slot) *slot; impl.slots)
            {
                while (slot)
                {
                    k ~= slot.key;
                    slot = slot.next;
                }
            }
        }
        return k;
    }

    @property inout(Value)[] values() inout @trusted
    {
        inout(Value)[] v;
        if (impl !is null)
        {
            // Preallocate output array for efficiency
            v.reserve(impl.nodes);
            foreach (inout(Slot) *slot; impl.slots)
            {
                while (slot)
                {
                    v ~= slot.value;
                    slot = slot.next;
                }
            }
        }
        return v;
    }

    @property typeof(this) rehash() @safe
    {
        size_t i;
        for (i=0; i < prime_list.length; i++)
        {
            if (impl.nodes <= prime_list[i])
                break;
        }
        size_t newlen = prime_list[i];
        Slot*[] newslots = alloc(newlen);

        foreach (slot; impl.slots)
        {
            while (slot)
            {
                auto next = slot.next;

                // Transplant slot into new hashtable.
                const j = slot.hash % newlen;
                slot.next = newslots[j];
                newslots[j] = slot;

                slot = next;
            }
        }

        // Remove references to slots in old hash table.
        if (impl.slots.ptr == impl.binit.ptr)
            impl.binit[] = null;
        else
            delete impl.slots;

        impl.slots = newslots;

        return this;
    }

    @property typeof(this) dup() /*nothrow pure*/ @safe
    {
        typeof(this) result;
        if (impl !is null)
        {
            foreach (slot; impl.slots)
            {
                while (slot)
                {
                    // FIXME: should avoid recomputing key hashes.
                    // FIXME: maybe do shallow copy if value type is immutable?
                    result[slot.key] = slot.value;
                    slot = slot.next;
                }
            }
        }
        return result;
    }

    @property auto byKey() pure nothrow @safe
    {
        static struct KeyRange
        {
            Range state;

            this(Impl *p) pure nothrow @safe
            {
                state = Range(p);
            }

            @property ref Key front() pure nothrow @safe
            {
                return state.front.key;
            }

            alias state this;
        }

        return KeyRange(impl);
    }

    @property auto byValue() pure nothrow @safe
    {
        static struct ValueRange
        {
            Range state;

            this(Impl *p) pure nothrow @safe
            {
                state = Range(p);
            }

            @property ref Value front() pure nothrow @safe
            {
                return state.front.value;
            }

            alias state this;
        }

        return ValueRange(impl);
    }
}

// Test reference semantics
unittest {
    AA!(string,int) aa, bb;
    aa["abc"] = 123;
    bb = aa;
    assert(aa.impl is bb.impl);

    aa["def"] = 456;
    assert(bb["def"] == 456);

    // TBD: should the case where aa is empty when it is assigned to bb work as
    // well?
}

unittest {
    AA!(dstring,int) aa;
    aa["mykey"d] = 10;

    assert(aa.get("mykey"d, 99) == 10);
    assert(aa.get("yourkey"d, 99) == 99);
}

unittest {
    AA!(wstring,bool) aa;
    aa["abc"w] = true;
    aa["def"w] = false;

    assert(("abc"w in aa) !is null);
    assert(("xyz"w in aa) is null);
}

unittest {
    AA!(char,char) aa;
    aa['x'] = 'y';
    aa['y'] = 'z';
    assert(aa[aa['x']] == 'z');
}

unittest {
    AA!(int,int) aa;
    aa[10] = 5;
    aa[20] = 17;
    aa[30] = 39;

    int valsum = 0;
    foreach (v; aa) {
        valsum += v;
    }
    assert(valsum == 5+17+39);

    int keysum = 0;
    valsum = 0;
    foreach (k,v; aa) {
        keysum += k;
        valsum += v;
    }
    assert(keysum == 10+20+30);
    assert(valsum == 5+17+39);
}

unittest {
    immutable int[] key1 = [1,2,3];
    immutable int[] key2 = [4,5,6];
    immutable int[] key3 = [1,3,5];
    AA!(immutable int[], char) aa, bb;
    aa[key1] = '1';
    aa[key2] = '2';
    aa[key3] = '3';
    bb[key3] = '3';
    bb[key2] = '2';
    bb[key1] = '1';

    assert(aa==bb);

    // .rehash should not invalidate equality
    bb.rehash;
    assert(aa==bb);
    assert(bb==aa);
}

unittest {
    AA!(char,int) aa;
    aa['a'] = 1;
    aa['b'] = 2;
    aa['c'] = 3;

    assert(aa.keys.sort == ['a', 'b', 'c']);
    assert(aa.values.sort == [1,2,3]);
}

unittest {
    AA!(int,int) aa;
    foreach (i; 0 .. 99) {
        aa[i*10] = i^^2;
    }
    aa.rehash;
    foreach (i; 0 .. 99) {
        assert(aa[i*10] == i^^2);
    }
}

unittest {
    AA!(int,string) aa;
    aa[100] = "a";
    aa[200] = "aa";
    aa[300] = "aaaa";
    int sum = 0;
    foreach (k; aa.byKey) {
        sum += k;
    }
    assert(sum == 600);

    string x;
    foreach(v; aa.byValue) {
        x ~= v;
    }
    assert(x == "aaaaaaa");
}

// issues 7512 & 7704
unittest {
    AA!(dstring,int) aa;
    aa["abc"] = 123;
    aa["def"] = 456;
    aa["ghi"] = 789;

    foreach (k, v; aa) {
        assert(aa[k] == v);
    }
}

// issue 7632
unittest {
    AA!(int,int) aa;
    foreach (idx; 0 .. 10) {
        aa[idx] = idx*2;
    }

    int[] z;
    foreach(v; aa.byValue) z ~= v;
    assert(z.sort == aa.values.sort);
}

// issue 6210
unittest {
    AA!(string,int) aa;
    aa["h"] = 1;
    assert(aa == aa.dup);
}

// issue 5685
unittest {
    int[2] foo = [1,2];
    AA!(int[2],string) aa;
    aa[foo] = "";
    assert(foo in aa);
    //FIXME: this needs to work
    //assert([1,2] in aa);
}

version(AAdebug) {
    void __rawAAdump(K,V)(AssociativeArray!(K,V) aa)
    {
        writefln("Hash at %x (%d entries):",
                 aa.impl, aa.impl is null ? -1: aa.impl.nodes);
        if (aa.impl !is null) {
            foreach(slot; aa.impl.slots) {
                while (slot) {
                    writefln("\tSlot %x:", cast(void*)slot);
                    writefln("\t\tHash:  %x", slot.hash);
                    writeln("\t\tKey:   ", slot.key);
                    writeln("\t\tValue: ", slot.value);

                    slot = slot.next;
                }
            }
        }
        writeln("End");
    }
}

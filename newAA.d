// vim:set ts=4 sw=4 expandtab:
// Developmental version of completely native AA implementation.

version=AAdebug;
version(AAdebug) {
    import std.conv;
    import std.stdio;
}

import core.exception;
import core.memory;

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

    struct Range
    {
        Slot*[] slots;
        Slot* curslot;
    }

    // Reference semantics
    Impl *impl;

    // Preset prime hash sizes for auto-rehashing.
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

    static @trusted Slot*[] alloc(size_t len)
    {
        auto slots = new Slot*[len];
        GC.setAttr(&slots, GC.BlkAttr.NO_INTERIOR);
        return slots;
    }

    @trusted inout(Slot) *findSlot(in Key key) inout {
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
    @safe @property pure size_t length() const { return impl.nodes; }

    @safe /*pure*/ Value get(in Key key, lazy Value defaultValue) const
    {
        auto s = findSlot(key);
        return (s is null) ? defaultValue : s.value;
    }

    @trusted Value *opBinaryRight(string op)(in Key key) if (op=="in")
    {
        auto slot = findSlot(key);
        return (slot) ? &slot.value : null;
    }

    @safe /*pure*/ Value opIndex(in Key key,
                                 string file=__FILE__, size_t line=__LINE__)
    {
        Value *valp = opBinaryRight!"in"(key);
        if (valp is null)
            throw new RangeError(file, line);

        return *valp;
    }

    // Why isn't getHash() pure?!
    /*pure*/ void opIndexAssign(in Value value, in Key key)
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

    @safe pure bool opEquals(inout typeof(this) that) inout
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

    @property inout(Key)[] keys() inout
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

    @property inout(Value)[] values() inout
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

    @safe @property typeof(this) rehash()
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

    @property pure const auto byKey()
    {
    }

    @property pure const auto byValue()
    {
    }
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

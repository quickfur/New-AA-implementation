import std.stdio;
import newAA;

alias newAA.AssociativeArray AA;

void test1() {
	AA!(string,int)  aasi;
	AA!(int,dstring) aaid;
	AA!(dstring,int) aadi;

	aasi["abc"] = 100;
	aasi["def"] = 200;

	assert(aasi["abc"] == 100);
	assert(aasi["def"] == 200);

	aaid[5] = "Five. Just five! OK?!";
	aaid[11] = "Eleven, without the seven";
	aaid[1000] = "One thousand";
	aaid[50000] = "Fifty thousand";
	aaid[65536] = "Sixty-five thousand something or other";
	aaid[1048576] = "One million and blah blah blah it's a megabyte!";

	writeln(aaid[1000]);
	writeln(aaid[50000]);
	assert((1234 in aaid) is null);

	writeln(aaid.keys);
	writeln(aaid.values);
}

// NOTE: this should only be necessary for development; once this code gets
// into druntime .toString should work automatically.
void dump(K,V)(AA!(K,V) aa) {
	write("[");
	string delim = "";
	foreach (key, value; aa) {
		static if (is(typeof(value)==string) ||
			is(typeof(value)==wstring) ||
			is(typeof(value)==dstring))
		{
			writef("%s%s: \"%s\"", delim, key, value);
		} else {
			writef("%s%s: %s", delim, key, value);
		}
		delim = ", ";
	}
	writeln("]");
}

void test2() {
	const int[] key1 = [ 1,2,3 ];
	const int[] key2 = [ 2,3,4 ];
	const int[] key3 = [ 3,4,5 ];

	AA!(const int[], string) aa1;
	aa1[key1] = "abc";
	aa1[key2] = "def";
	aa1[key3] = "ghi";

	dump(aa1);

	foreach (v; aa1) {
		writeln(v);
	}

	AA!(const int[], string) aa2;
	aa2[key3] = "ghi";
	aa2[key2] = "def";
	aa2[key1] = "abc";

	assert(aa2[key1] == "abc");

	aa2.rehash;

	assert(aa1==aa2);
}

void test3() {
	AA!(string,string) aa;
	aa["Hello"] = "Привет";
	aa["Goodbye"] = "Пока";
	aa["Thanks"] = "Спасибо";

	foreach (k; aa.byKey) {
		writeln(k);
	}

	foreach (v; aa.byValue) {
		writeln(v);
	}

	dump(aa);
}

struct S(K) {
	K key;

	template keyComparable(L) {
		enum bool keyComparable = is(typeof(key==L.init) == bool);
	}

	template keyDupCompat(L) {
		static if (__traits(compiles, L.init.dup))
			enum keyDupCompat = is(typeof(L.init.dup) : K);
		else
			enum keyDupCompat = false;
	}

	template keyIdupCompat(L) {
		static if (__traits(compiles, L.init.idup))
			enum keyIdupCompat = is(typeof(L.init.idup) : K);
		else
			enum keyIdupCompat = false;
	}

	template keyAssignable(L) {
		enum bool keyAssignable = is(L : K) || keyDupCompat!L ||
					keyIdupCompat!L;
	}

	bool equal(L)(L l) if (keyComparable!L)
	{
		return (key == l);
	}

	void set(L)(L l) if (keyAssignable!L)
	{
		static if (is(L : K)) {
			key = l;
		} else static if (keyDupCompat!L) {
			key = l.dup;
		} else static if (keyIdupCompat!L) {
			key = l.idup;
		}
	}
}

unittest {
	S!long s;
	ubyte b = 123;
	s.set(b);
	assert(s.equal(123UL));
}

unittest {
	S!dstring s;
	dchar[] t = "abc"d.dup;
	s.set(t);
	const(dchar)[] u = "abc"d;
	assert(s.equal(u));
}

void test4() {
	{
		auto s = S!string("abc");
		char[] t = "abc".dup;
		assert(s.equal(t));

		//int i = 123;
		//assert(s.equal(i));
	}
	{
		auto s = S!(char[])("abc".dup);
		string t = "abc";
		assert(s.equal(t));

		//s.set(123);
		s.set("def");
		assert(s.equal("def"));
	}
}

void main() {
	//test1();
	//test2();
	//test3();
	//test4();
}

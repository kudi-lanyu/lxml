# module-level API for namespace implementations

class NamespaceRegistryError(LxmlError):
    pass

class ElementBase(_Element):
    """All classes in namespace implementations must inherit from this
    one.  Note that subclasses *must not* override __init__ or __new__
    as there is absolutely undefined when these objects will be
    created or destroyed.  All state must be kept in the underlying
    XML."""
    pass

class XSLTElement(object):
    "NOT IMPLEMENTED YET!"
    pass

cdef object __NAMESPACE_CLASSES
__NAMESPACE_CLASSES = {}

def Namespace(ns_uri):
    if ns_uri:
        ns_utf = _utf8(ns_uri)
    else:
        ns_utf = None
    try:
        return __NAMESPACE_CLASSES[ns_utf]
    except KeyError:
        registry = __NAMESPACE_CLASSES[ns_utf] = _NamespaceRegistry(ns_uri)
        return registry

cdef class _NamespaceRegistry:
    "Dictionary-like registry for namespace implementations"
    cdef object _ns_uri
    cdef object _classes
    cdef object _extensions
    cdef object _xslt_elements
    def __init__(self, ns_uri):
        self._ns_uri = ns_uri
        self._classes = {}
        self._extensions = {}
        self._xslt_elements = {}

    def update(self, class_dict_iterable):
        """Forgivingly update the registry. If registered values are
        neither subclasses of ElementBase nor callable extension
        functions, or if their name starts with '_', they will be
        silently discarded. This allows registrations at the module or
        class level using vars(), globals() etc."""
        if hasattr(class_dict_iterable, 'iteritems'):
            class_dict_iterable = class_dict_iterable.iteritems()
        elif hasattr(class_dict_iterable, 'items'):
            class_dict_iterable = class_dict_iterable.items()
        for name, item in class_dict_iterable:
            if (name is None or name[:1] != '_') and callable(item):
                self[name] = item

    def __setitem__(self, name, item):
        if isinstance(item, (type, types.ClassType)) and issubclass(item, ElementBase):
            d = self._classes
        elif name is None:
            raise NamespaceRegistryError, "Registered name can only be None for elements."
        elif isinstance(item, (type, types.ClassType)) and issubclass(item, XSLTElement):
            d = self._xslt_elements
        elif callable(item):
            d = self._extensions
        else:
            raise NamespaceRegistryError, "Registered item must be callable."

        if name is None:
            name_utf = None
        else:
            name_utf = _utf8(name)
        d[name_utf] = item

    cdef __getitem__(self, name):
        cdef tree.PyObject* dict_result
        cdef char* c_name
        c_name = name
        dict_result = tree.PyDict_GetItem(self._classes, c_name)
        if dict_result is NULL:
            dict_result = tree.PyDict_GetItem(self._extensions, c_name)
        if dict_result is NULL:
            raise KeyError, "Name not registered."
        return <object>dict_result

    def clear(self):
        self._classes.clear()
        self._extensions.clear()
        #self.self._xslt_elements.clear()

cdef object _find_all_namespaces():
    "Hack to register all extension functions in XSLT"
    ns_uris = []
    for s in __NAMESPACE_CLASSES.keys():
        ns_uris.append(funicode(s))
    return ns_uris

cdef _NamespaceRegistry _find_namespace_registry(object ns_uri):
    cdef tree.PyObject* dict_result
    if ns_uri:
        ns_utf = _utf8(ns_uri)
        dict_result = tree.PyDict_GetItemString(__NAMESPACE_CLASSES, ns_utf)
    else:
        dict_result = tree.PyDict_GetItem(__NAMESPACE_CLASSES, None)
    if dict_result is NULL:
        raise
    else:
        return <_NamespaceRegistry>dict_result

cdef _find_extensions(namespaces):
    extension_dict = {}
    for ns_uri in namespaces:
        try:
            extensions = _find_namespace_registry(ns_uri)._extensions
        except KeyError:
            continue
        if extensions:
            extension_dict[ns_uri] = extensions
    return extension_dict

cdef object _find_element_class(char* c_namespace_utf,
                                char* c_element_name_utf):
    cdef tree.PyObject* dict_result
    cdef _NamespaceRegistry registry
    cdef object result
    if c_namespace_utf is not NULL:
        dict_result = tree.PyDict_GetItemString(__NAMESPACE_CLASSES, c_namespace_utf)
    else:
        dict_result = tree.PyDict_GetItem(__NAMESPACE_CLASSES, None)
    if dict_result is NULL:
        return _Element

    registry = <object>dict_result
    classes = registry._classes

    if c_element_name_utf is not NULL:
        dict_result = tree.PyDict_GetItemString(classes, c_element_name_utf)
    else:
        dict_result = NULL

    if dict_result is NULL:
        dict_result = tree.PyDict_GetItem(classes, None)

    if dict_result is not NULL:
        result = <object>dict_result
        return result
    else:
        return _Element

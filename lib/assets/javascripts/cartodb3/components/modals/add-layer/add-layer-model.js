var cdb = require('cartodb-deep-insights.js');
var Backbone = require('backbone');
var UploadModel = require('../../../data/upload-model');
var VisualizationFetchModel = require('../../../data/visualizations-fetch-model');
var TablesCollection = require('../../../data/tables-collection');
var TableModel = require('../../../data/table-model');

/**
 * Add layer model
 *
 * "Implements" the CreateListingModel.
 */
module.exports = cdb.core.Model.extend({
  defaults: {
    type: 'addLayer',
    contentPane: 'listing', // [listing, loading]
    listing: 'datasets', // [import, datasets, scratch]
    collectionFetched: false,
    activeImportPane: 'file'
  },

  initialize: function (attrs, opts) {
    if (!opts.userModel) throw new Error('userModel is required');
    if (!opts.configModel) throw new Error('configModel is required');
    if (!opts.visMap) throw new Error('visMap is required');

    this._userModel = opts.userModel;
    this._visMap = opts.visMap;
    this._configModel = opts.configModel;

    this.uploadModel = new UploadModel({
      create_vis: false
    }, {
      userModel: this._userModel,
      configModel: this._configModel
    });

    this.selectedDatasets = new Backbone.Collection();
    this.tablesCollection = new TablesCollection([], {
      configModel: this._configModel
    });
    this.visualizationFetchModel = new VisualizationFetchModel({
      content_type: 'datasets',
      library: this.showLibrary()
    });
    this._initBinds();
    this._maybePrefetchDatasets();
  },

  canSelect: function (dataset) {
    return dataset.get('selected') || this.selectedDatasets.length < 1; // for now only allow 1 item
  },

  showLibrary: function () {
    return false;
  },

  showDatasets: function () {
    return true;
  },

  setActiveImportPane: function (name) {
    this.set('activeImportPane', name);
  },

  canFinish: function () {
    if (this.get('listing') === 'import') {
      return this.uploadModel.isValidToUpload();
    } else if (this.get('listing') === 'datasets') {
      return this.selectedDatasets.length > 0;
    }
  },

  finish: function () {
    if (this.get('listing') === 'import') {
      // TODO: what to do with cdb.god
      // cdb.god.trigger('importByUploadData', this.uploadModel.toJSON(), this);
      console.log('TODO: importByUploadData', this.uploadModel.toJSON());
    } else if (this.get('listing') === 'datasets') {
      var mdl = this.selectedDatasets.at(0);
      if (mdl.get('type') === 'remote') {
        var d = {
          create_vis: false,
          type: 'remote',
          value: mdl.get('name'),
          remote_visualization_id: mdl.get('id'),
          size: mdl.get('external_source') ? mdl.get('external_source').size : undefined
        };
        // See BackgroundImporter where the same event is bound to be handled..
        // TODO: what to do with cdb.god
        // cdb.god.trigger('importByUploadData', d, this);
        console.log('TODO: importByUploadData', d);
      } else {
        this._addNewLayer(mdl.tableMetadata().get('name'));
      }
    }
  },

  getImportState: function () {
    return this.get('activeImportPane');
  },

  showGuessingToggler: function () {
    return this.get('listing') === 'import';
  },

  showPrivacyToggler: function () {
    return this.get('listing') === 'import';
  },

  createFromScratch: function () {
    var self = this;
    this.set('contentPane', 'creatingFromScratch');
    var tableModel = new TableModel();
    tableModel.save({}, {
      success: function () {
        self._addNewLayer(tableModel.get('name'));
      },
      error: function () {
        self.set('contentPane', 'addLayerFailed');
      }
    });
  },

  _initBinds: function () {
    this.uploadModel.bind('change', function () {
      this.trigger('change:upload', this);
    }, this);
    this.visualizationFetchModel.bind('change', this._fetchCollection, this);
    this.bind('change:listing', this._maybePrefetchDatasets);

    this.tablesCollection.bind('change:selected', function (changedModel, wasSelected) {
      this.selectedDatasets[ wasSelected ? 'add' : 'remove' ](changedModel);
    }, this);
    this.tablesCollection.bind('reset', function () {
      this.selectedDatasets.each(function (model) {
        var sameModel = this.tablesCollection.get(model.id);
        if (sameModel) {
          sameModel.set('selected', true);
        }
      }, this);
    }, this);
  },

  _maybePrefetchDatasets: function () {
    if (this.get('listing') === 'datasets' && !this.get('collectionFetched') && !this.visualizationFetchModel.isSearching()) {
      this.set('collectionFetched', true);
      this._fetchCollection();
    }
  },

  _fetchCollection: function () {
    var params = this.visualizationFetchModel.attributes;
    var types;

    if (this.visualizationFetchModel.isSearching()) {
      // Supporting search in data library and user datasets at the same time
      types = 'table,remote';
    } else {
      types = params.library ? 'remote' : 'table';
    }

    this.tablesCollection.fetch({
      data: {
        locked: '',
        q: params.q,
        page: params.page,
        tags: params.tag,
        shared: params.shared,
        only_liked: params.liked,
        type: '',
        types: types
      }
    });
  },

  _onCollectionChange: function () {
    this.selectedDatasets.reset(
      this.tablesCollection.where({ selected: true })
    );
  },

  _addNewLayer: function (tableName) {
    this.set('contentPane', 'addingNewLayer');
    console.log('TODO: review this._visMap.addCartodbLayerFromTable');

    // var self = this;
    // this._visMap.addCartodbLayerFromTable(tableName, this.user.get('username'), {
    //   vis: this.vis,
    //   success: function () {
    //     // layers need to be saved because the order may changed
    //     console.log("TODO: :scream: _visMap.layers.saveLayers");
    //     self._visMap.layers.saveLayers();
    //     self.trigger('addLayerDone');
    //   },
    //   error: function () {
    //     self.set('contentPane', 'addLayerFailed');
    //   }
    // });
  }

});
'use strict';

var React = require("react"),
    $ = require("jquery"),
    dd = require("jquery.dd");

const ProcessSelector = React.createClass({
  render() {
    return (
      <div className="process-selector jumbotron">
        <h1>Welcome!</h1>
        <h4>Select a process to get started:</h4>
        <form>
          <div className="form-group">
            <label>Device</label>
            <div>
              <select ref="devices">
                <option value="1">Local System</option>
                <option value="2">iPhone</option>
              </select>
            </div>
          </div>
          <div className="form-group">
            <label>Process</label>
            <div>
              <select ref="processes">
                <option value="1234">Facebook</option>
                <option value="5678">Twitter</option>
              </select>
            </div>
          </div>
          <button type="submit" className="btn btn-primary large">Start</button>
        </form>
      </div>
    );
  },
  componentDidMount() {
      this._updateDropdowns();
  },
  componentDidUpdate(prevProps, prevState) {
      this._updateDropdowns();
  },
  _updateDropdowns() {
      $(React.findDOMNode(this.refs.devices)).msDropDown();
      $(React.findDOMNode(this.refs.processes)).msDropDown();
  }
});

module.exports = ProcessSelector;
